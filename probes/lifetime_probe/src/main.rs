fn main() {
    // Test subject: survives SIGHUP so crash-cleanup cannot pass by hangup alone.
    let old = unsafe { libc::signal(libc::SIGHUP, libc::SIG_IGN) };
    if old == libc::SIG_ERR {
        eprintln!("{}", std::io::Error::last_os_error());
        std::process::exit(1);
    }
    println!("ready");
    // Last-resort bound for a failed harness; acceptance requires death in 3 s.
    std::thread::sleep(std::time::Duration::from_secs(30));
}
