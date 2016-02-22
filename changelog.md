# WinRM-fs Gem Changelog

# 0.3.1
- Widen logging version constraints to include 2.0 (matching WinRM core gem)

# 0.3.0
- Jetisons `CommandExecutor` now living in the core WinRM gem and swaps in implementation currently used in the winrm-transport gem. These changes should have little visible effect on current consumers of the `FileManager` class with these exceptions:
  - BREAKING CHANGE: When uploading a directory and the destination directory exists on the endpoint, the source base directory will be created below the destination directory on the endpoint and the source directory contents will be unzipped to that location. Prior to this release, the contents of the source directory would be unzipped to an existing destination directory without creating the source base directory. This new behavior is more consistent with SCP and other well known shell copy commands.
  - `Upload` may now receive an array of source files and directories rather than just a single file or directory path.

# 0.2.4
- Fix issue 21, downloading files is extremely slow.
- Add zip file creation debug logging.

# 0.2.3
- Fix yielding progress data, issue #23

# 0.2.2
- Fix powershell streams leaking to standard error breaking Windows 10, issue #18

# 0.2.1
- Fixed issue 16 creating zip file on Windows

# 0.2.0
- Redesigned temp zip file creation system
- Fixed lots of small edge case issues especially with directory uploads
- Simplified file manager upload method API to take only a single source file or directory
- Expanded acceptable username and hostnames for rwinrmcp

# 0.1.0
- Initial alpha quality release
