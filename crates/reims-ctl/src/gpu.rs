//! The host's GPUs a VM can be given.
//!
//! On Linux the library runs on Vulkan, and picks the first discrete GPU, then the first
//! integrated one, in the loader's order. A VM can name another: its Vulkan driver's manifest
//! (an ICD JSON file, which `VK_DRIVER_FILES` limits the loader to) and, where that driver
//! drives several GPUs, the PCI device ID (`VK_LOADER_DEVICE_ID_FILTER`). The list comes from
//! asking each manifest's driver in a child process (`reims-ctl __vulkan-probe`), so a driver
//! that hangs or crashes costs only that one.
//!
//! Each GPU's driver is also asked whether it imports a page of shared memory through
//! `VK_EXT_external_memory_host`, as the library imports guest RAM, a shared mapping of a memfd
//! (docs/qemu.md, "The files behind guest RAM"). AMD's drivers refuse it: libdrm's
//! `amdgpu_create_bo_from_user_mem` asks the kernel for anonymous memory only
//! (`AMDGPU_GEM_USERPTR_ANONONLY`), and amdgpu refuses a mapping with a file behind it, so the
//! library dies at its first import of guest RAM there. A start refuses such a GPU
//! (`runtime::preflight`), and the lists mark it.
//!
//! On macOS the library runs on the system's default Metal device; there is nothing to choose.

use serde::{Deserialize, Serialize};
use std::path::PathBuf;

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct GpuInfo {
    pub name: String,
    pub vendor_id: u32,
    pub device_id: u32,
    /// discrete, integrated, virtual, cpu or other.
    pub kind: String,
    pub driver_file: PathBuf,
    /// Whether another GPU shares the driver (the device ID then picks it).
    #[serde(default)]
    pub shares_driver: bool,
    /// Whether the driver imported a page of shared memory, as the library imports guest RAM:
    /// `None` where the probe could not ask (module docs).
    #[serde(default)]
    pub imports_shared_memory: Option<bool>,
}

/// Why a GPU whose driver refuses shared memory runs no guest (module docs).
pub const NO_SHARED_MEMORY: &str = "cannot run guests: its driver imports no shared memory, which \
     guest RAM is (AMD's Linux drivers import only private memory)";

impl GpuInfo {
    pub fn label(&self) -> String {
        let file = self
            .driver_file
            .file_name()
            .map(|f| f.to_string_lossy().into_owned())
            .unwrap_or_default();
        let note = match self.runs_guests() {
            true => String::new(),
            false => format!(": {NO_SHARED_MEMORY}"),
        };
        format!("{} ({}, {file}){note}", self.name, self.kind)
    }

    /// Whether the library can run a guest on the GPU: not where its driver refused shared
    /// memory.
    pub fn runs_guests(&self) -> bool {
        self.imports_shared_memory != Some(false)
    }

    pub fn to_config(&self) -> crate::vm::Gpu {
        crate::vm::Gpu {
            driver_file: Some(self.driver_file.clone()),
            device_id: self.shares_driver.then_some(self.device_id),
            name: Some(self.name.clone()),
        }
    }
}

/// The Vulkan driver manifests the loader would read, in its search order (the Khronos loader's
/// Linux search paths).
pub fn icd_files() -> Vec<PathBuf> {
    let home = crate::paths::home();
    let env_list = |var: &str, default: &str| -> Vec<PathBuf> {
        std::env::var(var)
            .ok()
            .filter(|v| !v.is_empty())
            .unwrap_or_else(|| default.to_string())
            .split(':')
            .filter(|s| !s.is_empty())
            .map(PathBuf::from)
            .collect()
    };
    let mut dirs = Vec::new();
    dirs.push(
        std::env::var_os("XDG_CONFIG_HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| home.join(".config")),
    );
    dirs.extend(env_list("XDG_CONFIG_DIRS", "/etc/xdg"));
    dirs.push("/etc".into());
    dirs.push(
        std::env::var_os("XDG_DATA_HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| home.join(".local/share")),
    );
    dirs.extend(env_list("XDG_DATA_DIRS", "/usr/local/share:/usr/share"));
    let mut files = Vec::new();
    for d in dirs {
        let Ok(rd) = std::fs::read_dir(d.join("vulkan/icd.d")) else {
            continue;
        };
        let mut here: Vec<PathBuf> = rd
            .flatten()
            .map(|e| e.path())
            .filter(|p| p.extension().is_some_and(|e| e == "json"))
            .collect();
        here.sort();
        for p in here {
            if !files.contains(&p) {
                files.push(p);
            }
        }
    }
    files
}

/// The host's GPUs, each with the driver manifest that reaches it.
pub fn list() -> Vec<GpuInfo> {
    if !cfg!(target_os = "linux") {
        return Vec::new();
    }
    let Ok(exe) = std::env::current_exe() else {
        return Vec::new();
    };
    let handles: Vec<_> = icd_files()
        .into_iter()
        .map(|file| {
            let exe = exe.clone();
            std::thread::spawn(move || probe(&exe, &file))
        })
        .collect();
    let mut gpus: Vec<GpuInfo> = handles
        .into_iter()
        .filter_map(|h| h.join().ok())
        .flatten()
        .collect();
    // One GPU can be reached through two manifests (a 32-bit and a 64-bit one, say): keep the
    // first.
    let mut seen = Vec::new();
    gpus.retain(|g| {
        let key = (
            g.vendor_id,
            g.device_id,
            g.name.clone(),
            g.driver_file.file_name().map(|f| f.to_os_string()),
        );
        if seen.contains(&key) {
            false
        } else {
            seen.push(key);
            true
        }
    });
    let counts: Vec<usize> = gpus
        .iter()
        .map(|g| {
            gpus.iter()
                .filter(|o| o.driver_file == g.driver_file)
                .count()
        })
        .collect();
    for (g, n) in gpus.iter_mut().zip(counts) {
        g.shares_driver = n > 1;
    }
    let rank = |k: &str| match k {
        "discrete" => 0,
        "integrated" => 1,
        "virtual" => 2,
        "other" => 3,
        _ => 4,
    };
    gpus.sort_by_key(|g| rank(&g.kind));
    gpus
}

/// The GPU of `list` the library takes for a VM given `gpu`: the first of those its driver
/// manifest and device ID keep, or with neither the first of all, as `list` puts discrete GPUs
/// first. `None` where none is kept, as for a manifest `list` does not name.
pub fn chosen<'a>(gpu: &crate::vm::Gpu, list: &'a [GpuInfo]) -> Option<&'a GpuInfo> {
    list.iter().find(|g| {
        gpu.driver_file.as_ref().is_none_or(|f| *f == g.driver_file)
            && gpu.device_id.is_none_or(|id| id == g.device_id)
    })
}

fn probe(exe: &std::path::Path, file: &std::path::Path) -> Vec<GpuInfo> {
    use std::process::{Command, Stdio};
    let child = Command::new(exe)
        .arg("__vulkan-probe")
        .env("VK_DRIVER_FILES", file)
        .env("VK_ICD_FILENAMES", file)
        .env("VK_LOADER_LAYERS_DISABLE", "~all~")
        .env_remove("VK_LOADER_DEVICE_ID_FILTER")
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn();
    let Ok(mut child) = child else {
        return Vec::new();
    };
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(15);
    loop {
        match child.try_wait() {
            Ok(Some(_)) => break,
            Ok(None) if std::time::Instant::now() < deadline => {
                std::thread::sleep(std::time::Duration::from_millis(50))
            }
            _ => {
                let _ = child.kill();
                let _ = child.wait();
                return Vec::new();
            }
        }
    }
    let mut out = String::new();
    use std::io::Read;
    let _ = child.stdout.take().map(|mut s| s.read_to_string(&mut out));
    out.lines()
        .filter_map(|l| serde_json::from_str::<GpuInfo>(l).ok())
        .map(|mut g| {
            g.driver_file = file.to_path_buf();
            g
        })
        .collect()
}

/// `reims-ctl __vulkan-probe`: one JSON line per physical device the loader finds.
#[cfg(target_os = "linux")]
pub fn probe_main() -> i32 {
    use ash::vk;
    // SAFETY: loads the system's Vulkan loader; the calls below follow the API's rules.
    unsafe {
        let Ok(entry) = ash::Entry::load() else {
            return 1;
        };
        let app = vk::ApplicationInfo::default().api_version(vk::make_api_version(0, 1, 1, 0));
        let ci = vk::InstanceCreateInfo::default().application_info(&app);
        let Ok(instance) = entry.create_instance(&ci, None) else {
            return 1;
        };
        if let Ok(devices) = instance.enumerate_physical_devices() {
            for pd in devices {
                let p = instance.get_physical_device_properties(pd);
                let name = p
                    .device_name_as_c_str()
                    .map(|c| c.to_string_lossy().into_owned())
                    .unwrap_or_default();
                let kind = match p.device_type {
                    vk::PhysicalDeviceType::DISCRETE_GPU => "discrete",
                    vk::PhysicalDeviceType::INTEGRATED_GPU => "integrated",
                    vk::PhysicalDeviceType::VIRTUAL_GPU => "virtual",
                    vk::PhysicalDeviceType::CPU => "cpu",
                    _ => "other",
                };
                let info = GpuInfo {
                    name,
                    vendor_id: p.vendor_id,
                    device_id: p.device_id,
                    kind: kind.into(),
                    driver_file: PathBuf::new(),
                    shares_driver: false,
                    imports_shared_memory: imports_shared_memory(&instance, pd, &p),
                };
                println!("{}", serde_json::to_string(&info).unwrap());
            }
        }
        instance.destroy_instance(None);
    }
    0
}

/// Whether `pd`'s driver imports a page of shared memory, a shared mapping of a memfd as QEMU's
/// `memory-backend-memfd,share=on` maps guest RAM, through `VK_EXT_external_memory_host`, as the
/// library does: `Some(false)` where the device lacks the extension, has no host-visible coherent
/// memory type for the page, or refuses the import as the library's runtime counts a refusal
/// (`VK_ERROR_INVALID_EXTERNAL_HANDLE`, or `VK_ERROR_UNKNOWN`, which RADV of Mesa 26.0 answers);
/// `None` where the probe could not ask.
///
/// # Safety
///
/// `pd` is one of `instance`'s physical devices, and `p` its properties.
#[cfg(target_os = "linux")]
unsafe fn imports_shared_memory(
    instance: &ash::Instance,
    pd: ash::vk::PhysicalDevice,
    p: &ash::vk::PhysicalDeviceProperties,
) -> Option<bool> {
    use ash::vk;
    let ext = ash::ext::external_memory_host::NAME;
    // SAFETY: the caller's `pd` and `p`; the device made here is destroyed before it returns,
    // after the import is freed, and the page outlives both.
    unsafe {
        let has = instance.enumerate_device_extension_properties(pd).ok()?;
        if !has.iter().any(|e| e.extension_name_as_c_str() == Ok(ext)) {
            return Some(false);
        }
        if p.api_version < vk::API_VERSION_1_1 {
            return None;
        }
        let mut host = vk::PhysicalDeviceExternalMemoryHostPropertiesEXT::default();
        let mut props = vk::PhysicalDeviceProperties2::default().push_next(&mut host);
        instance.get_physical_device_properties2(pd, &mut props);
        let page = u64::try_from(libc::sysconf(libc::_SC_PAGESIZE)).ok()?;
        let len = page.max(host.min_imported_host_pointer_alignment);
        let shared = SharedPage::new(usize::try_from(len).ok()?)?;
        let priorities = [1.0f32];
        let queues = [vk::DeviceQueueCreateInfo::default()
            .queue_family_index(0)
            .queue_priorities(&priorities)];
        let names = [ext.as_ptr()];
        let info = vk::DeviceCreateInfo::default()
            .queue_create_infos(&queues)
            .enabled_extension_names(&names);
        let device = instance.create_device(pd, &info, None).ok()?;
        let answer = import(instance, pd, &device, shared.at, len);
        device.destroy_device(None);
        answer
    }
}

/// The import of `len` bytes at `at` on `device` (`imports_shared_memory`), freed at once.
///
/// # Safety
///
/// `device` is made on `pd` with `VK_EXT_external_memory_host`, and the bytes stay mapped
/// meanwhile.
#[cfg(target_os = "linux")]
unsafe fn import(
    instance: &ash::Instance,
    pd: ash::vk::PhysicalDevice,
    device: &ash::Device,
    at: *mut std::ffi::c_void,
    len: u64,
) -> Option<bool> {
    use ash::vk;
    let refused = |e: vk::Result| match e {
        vk::Result::ERROR_INVALID_EXTERNAL_HANDLE | vk::Result::ERROR_UNKNOWN => Some(false),
        _ => None,
    };
    let handle = vk::ExternalMemoryHandleTypeFlags::HOST_ALLOCATION_EXT;
    let ext = ash::ext::external_memory_host::Device::new(instance, device);
    let mut host = vk::MemoryHostPointerPropertiesEXT::default();
    // SAFETY: the caller's device and bytes; the memory is freed before this returns.
    unsafe {
        let asked = (ext.fp().get_memory_host_pointer_properties_ext)(
            device.handle(),
            handle,
            at,
            &mut host,
        );
        if asked != vk::Result::SUCCESS {
            return refused(asked);
        }
        let types = instance.get_physical_device_memory_properties(pd);
        let wanted = vk::MemoryPropertyFlags::HOST_VISIBLE | vk::MemoryPropertyFlags::HOST_COHERENT;
        let index = (0..types.memory_type_count).find(|&i| {
            host.memory_type_bits & (1 << i) != 0
                && usize::try_from(i)
                    .ok()
                    .and_then(|i| types.memory_types.get(i))
                    .is_some_and(|t| t.property_flags.contains(wanted))
        });
        let Some(index) = index else {
            return Some(false);
        };
        let mut pointer = vk::ImportMemoryHostPointerInfoEXT::default()
            .handle_type(handle)
            .host_pointer(at);
        let info = vk::MemoryAllocateInfo::default()
            .allocation_size(len)
            .memory_type_index(index)
            .push_next(&mut pointer);
        match device.allocate_memory(&info, None) {
            Ok(memory) => {
                device.free_memory(memory, None);
                Some(true)
            }
            Err(e) => refused(e),
        }
    }
}

/// A shared mapping, read and write, of a fresh memfd, as QEMU maps guest RAM; unmapped when it
/// drops. The file goes with the mapping.
#[cfg(target_os = "linux")]
struct SharedPage {
    at: *mut std::ffi::c_void,
    len: usize,
}

#[cfg(target_os = "linux")]
impl SharedPage {
    fn new(len: usize) -> Option<SharedPage> {
        use std::os::fd::{AsRawFd, FromRawFd, OwnedFd};
        // SAFETY: a new file of this process's, closed when `fd` drops, and a new mapping of it,
        // which `SharedPage` owns.
        unsafe {
            let fd = libc::memfd_create(c"reims-ctl-probe".as_ptr(), libc::MFD_CLOEXEC);
            if fd < 0 {
                return None;
            }
            let fd = OwnedFd::from_raw_fd(fd);
            if libc::ftruncate(fd.as_raw_fd(), libc::off_t::try_from(len).ok()?) != 0 {
                return None;
            }
            let at = libc::mmap(
                std::ptr::null_mut(),
                len,
                libc::PROT_READ | libc::PROT_WRITE,
                libc::MAP_SHARED,
                fd.as_raw_fd(),
                0,
            );
            (at != libc::MAP_FAILED).then_some(SharedPage { at, len })
        }
    }
}

#[cfg(target_os = "linux")]
impl Drop for SharedPage {
    fn drop(&mut self) {
        // SAFETY: the mapping `new` made, which nothing imports any more.
        unsafe { libc::munmap(self.at, self.len) };
    }
}

#[cfg(not(target_os = "linux"))]
pub fn probe_main() -> i32 {
    1
}

#[cfg(test)]
mod tests {
    use super::*;

    fn gpu(name: &str, file: &str, device_id: u32, imports: Option<bool>) -> GpuInfo {
        GpuInfo {
            name: name.into(),
            vendor_id: 0x1002,
            device_id,
            kind: "discrete".into(),
            driver_file: file.into(),
            shares_driver: false,
            imports_shared_memory: imports,
        }
    }

    #[test]
    fn a_probe_line_without_the_answer_reads_as_unasked() {
        let line =
            r#"{"name":"G","vendor_id":4098,"device_id":29824,"kind":"discrete","driver_file":""}"#;
        let g: GpuInfo = serde_json::from_str(line).unwrap();
        assert_eq!(g.imports_shared_memory, None);
        assert!(g.runs_guests());
    }

    #[test]
    fn only_a_refusal_of_shared_memory_stops_guests() {
        assert!(gpu("A", "/a.json", 1, Some(true)).runs_guests());
        assert!(gpu("A", "/a.json", 1, None).runs_guests());
        let amd = gpu(
            "AMD Radeon RX 7600 (RADV NAVI33)",
            "/icd/radeon_icd.json",
            1,
            Some(false),
        );
        assert!(!amd.runs_guests());
        assert_eq!(
            amd.label(),
            format!(
                "AMD Radeon RX 7600 (RADV NAVI33) (discrete, radeon_icd.json): {NO_SHARED_MEMORY}"
            )
        );
    }

    #[test]
    fn the_chosen_gpu_is_the_first_the_config_keeps() {
        let list = [
            gpu("dGPU", "/icd/radeon.json", 0x7480, Some(false)),
            gpu("iGPU", "/icd/radeon.json", 0x15bf, Some(false)),
            gpu("nv", "/icd/nvidia.json", 0x2204, Some(true)),
        ];
        let of = |file: Option<&str>, id: Option<u32>| {
            let g = crate::vm::Gpu {
                driver_file: file.map(Into::into),
                device_id: id,
                name: None,
            };
            chosen(&g, &list).map(|g| g.name.clone())
        };
        assert_eq!(of(None, None).as_deref(), Some("dGPU"));
        assert_eq!(of(Some("/icd/radeon.json"), None).as_deref(), Some("dGPU"));
        assert_eq!(
            of(Some("/icd/radeon.json"), Some(0x15bf)).as_deref(),
            Some("iGPU")
        );
        assert_eq!(of(Some("/icd/nvidia.json"), None).as_deref(), Some("nv"));
        assert_eq!(of(Some("/icd/other.json"), None), None);
    }
}
