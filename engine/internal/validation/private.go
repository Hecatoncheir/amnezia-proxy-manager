package validation

// PrivateDirectory создаёт каталог конфигурации с ACL владельца/SYSTEM или 0700.
func PrivateDirectory() (string, error) { return privateDirectory() }
