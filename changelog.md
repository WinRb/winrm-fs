# WinRM-fs Gem Changelog

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
