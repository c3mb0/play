//! Cooperative fixtures, not a generic process diagnostic.
use std::{
    fs::OpenOptions,
    io::{self, Read, Write},
    path::Path,
    process::{Command, Stdio},
    thread,
    time::Duration,
};
fn note(dir: &Path, name: &str, text: &str) -> io::Result<()> {
    let mut f = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(dir.join(name))?;
    writeln!(f, "{text}")?;
    f.sync_all()
}
fn ready() -> io::Result<()> {
    println!("READY");
    io::stdout().flush()
}
fn main() -> io::Result<()> {
    unsafe {
        libc::alarm(10);
    }
    let args: Vec<String> = std::env::args().collect();
    let mode = args.get(1).map(String::as_str).unwrap_or("");
    let dir = Path::new(
        args.get(2)
            .ok_or_else(|| io::Error::other("missing case directory"))?,
    );
    match mode {
        "holder" => {
            thread::sleep(Duration::from_secs(8));
        }
        "hold" => {
            ready()?;
            thread::sleep(Duration::from_secs(9));
        }
        "flood" => {
            ready()?;
            thread::sleep(Duration::from_millis(400));
            note(
                dir,
                "write_started",
                "cooperative intent before stdout write",
            )?;
            io::stdout().write_all(&vec![b'X'; 262_144])?;
            io::stdout().flush()?;
            note(dir, "write_finished", "stdout write completed")?;
        }
        "held_output" | "descendant" => {
            let child = Command::new(std::env::current_exe()?)
                .arg("holder")
                .arg(dir)
                .stdin(Stdio::null())
                .stdout(Stdio::inherit())
                .stderr(Stdio::inherit())
                .spawn()?;
            note(dir, "holder.pid", &child.id().to_string())?;
            // Child::drop does not kill: intentional inherited-descriptor fixture.
            drop(child);
            ready()?;
            if mode == "held_output" {
                let mut byte = [0];
                io::stdin().read_exact(&mut byte)?;
                if byte != [b'x'] {
                    return Err(io::Error::other("expected x"));
                }
            } else {
                thread::sleep(Duration::from_secs(9));
            }
        }
        _ => return Err(io::Error::other("unknown fixture")),
    }
    Ok(())
}
