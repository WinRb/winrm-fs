# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

## [1.3.7]

- Fix compatibility with winrm 2.4.0: use stdlib `logger` instead of the `logging` gem, which winrm no longer requires (#99)
- Defer `rubyzip` and `csv` requires and drop the unused `logger` require (#100)
- Replace `erubi` with stdlib `erb`; also fixes Windows paths containing `&` being escaped as `&amp;` in generated PowerShell (#101)
- Bump `rubyzip` to `~> 3.4` to fix CVE-2026-85396 (High, path traversal on extract; no backport to 2.x)
