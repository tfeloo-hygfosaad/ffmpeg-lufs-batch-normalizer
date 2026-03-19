install:
	install -Dm755 ./bin/normalize_lufs $(HOME)/.local/bin/normalize_lufs

uninstall:
	rm -f $(HOME)/.local/bin/normalize_lufs