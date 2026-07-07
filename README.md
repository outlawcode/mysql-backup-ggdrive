# MySQL to Google Drive Backup (via rclone)

An open-source tool to automatically backup MySQL databases on Linux, compress them, and securely upload them to Google Drive with retention policies.

## System Requirements
- Linux (Ubuntu, CentOS, Debian, etc.) or macOS
- `mysqldump` (Usually bundled with MySQL/MariaDB)
- `rclone` (Will be installed automatically by the setup script on Linux)

## 1. Quick Installation (1-line)

Run the following command in your terminal (Remember to replace `YOUR_GITHUB_USERNAME` with your actual GitHub username):

```bash
curl -sL https://raw.githubusercontent.com/outlawcode/mysql-backup-ggdrive/main/install.sh | sudo bash
```
*(After installation, the `mygdrive-backup` command will be available globally)*

## 2. Google Drive Authentication (Rclone Config)

To grant the tool access to your Google Drive, configure rclone once:

```bash
rclone config
```
1. Press `n` for a New remote.
2. Name it: `gdrive`
3. Under `Storage`, select Google Drive (usually number `18` or type `drive`).
4. Leave Client ID / Client Secret empty (press Enter).
5. Follow the on-screen instructions to get the token and authenticate via your web browser.

## 3. Usage

To run the interactive configuration wizard:
```bash
mygdrive-backup
```

To run a backup manually via CLI:
```bash
mygdrive-backup --db "db1,db2" --user root --pass "secret123" --remote gdrive:BackupFolder --keep-days 7
```

## 4. Testing on macOS with MAMP
If you are testing this script on macOS using MAMP, make sure the `mysql` and `mysqldump` binaries are accessible in your `$PATH`.
You can add them temporarily by running:
```bash
export PATH="/Applications/MAMP/Library/bin:$PATH"
```
Then, you can run `./backup.sh` directly from the project folder without using the `install.sh` script (make sure to `brew install rclone` first).
