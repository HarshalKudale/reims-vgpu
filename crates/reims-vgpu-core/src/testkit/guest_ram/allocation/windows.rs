//! Virtual allocations: a heap block cannot be replaced by a Windows file view.

use std::alloc::Layout;
use std::ffi::c_void;

#[link(name = "kernel32")]
unsafe extern "system" {
    fn VirtualAlloc(addr: *mut c_void, len: usize, kind: u32, protection: u32) -> *mut c_void;
    fn VirtualFree(addr: *mut c_void, len: usize, kind: u32) -> i32;
    fn UnmapViewOfFile(addr: *const c_void) -> i32;
}

/// Windows reserves addresses at 64 KiB boundaries; commit whole blocks for an in-place remap.
pub unsafe fn alloc_zeroed(layout: Layout) -> *mut u8 {
    let Some(len) = layout.size().checked_add(0xffff).map(|n| n & !0xffff) else {
        return std::ptr::null_mut();
    };
    // SAFETY: a fresh, zero-filled reservation; no caller memory is replaced.
    unsafe { VirtualAlloc(std::ptr::null_mut(), len, 0x3000, 4) }.cast()
}

/// Releases the allocation, or the file view the death harness put at the same address.
pub unsafe fn dealloc(ptr: *mut u8, _layout: Layout) {
    // SAFETY: the region owns this reservation or remapped view, and no other reference remains.
    if unsafe { VirtualFree(ptr.cast(), 0, 0x8000) } == 0 {
        // SAFETY: when VirtualFree refuses it, this region owns a mapped file view instead.
        assert_ne!(unsafe { UnmapViewOfFile(ptr.cast()) }, 0);
    }
}
