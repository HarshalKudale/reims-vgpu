//! Self-update: the checkout reims-ctl was installed from pulls, and scripts/install-ctl.sh
//! builds and installs the new reims-ctl and QEMU. The new QEMU goes beside the old one, so
//! running VMs keep theirs; the new reims-ctl replaces this binary, so restart it afterwards.

use crate::install::Install;
use anyhow::{Context, Result, bail};
use std::process::Command;

pub fn update() -> Result<()> {
    let i = Install::load().context(
        "no install record: run scripts/install-ctl.sh in your reims-vgpu checkout once, and \
         reims-ctl update can use it from then on",
    )?;
    let script = i.repo.join("scripts/install-ctl.sh");
    if !script.is_file() {
        bail!("{} is missing: was the checkout moved?", script.display());
    }
    let status = Command::new("bash")
        .arg(&script)
        .arg("--update")
        .current_dir(&i.repo)
        .status()
        .context("run bash")?;
    if !status.success() {
        bail!("the update failed (exit {})", status.code().unwrap_or(-1));
    }
    Ok(())
}
