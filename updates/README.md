# Beta 更新接口 v1

GET https://raw.githubusercontent.com/DavidGump-070660/Dolikepet/main/updates/beta.json

字段：schema（固定 1）、channel（beta）、platform（windows-x86_64）、version（beta主.次.修订）、release_url、download_url、size_bytes（ZIP 字节数）、sha256（ZIP SHA-256）。

客户端按三个数字比较版本，只提示较新版本；不启动远程程序。更新包先上传并校验，再更新此指针。每个 Release 附独立 update.json 和 SHA256SUMS.txt。beta0.1.0 提供手动检查与发布页下载，安装时先退出程序，保留饭盆、胃袋和个人设置。
