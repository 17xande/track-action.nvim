NVIM := nvim --headless -u tests/minimal_init.lua

.PHONY: test test-lazyvim

test:
	$(NVIM) -c "luafile tests/parser_spec.lua" -c "qa"
	$(NVIM) -c "luafile tests/mappings_spec.lua" -c "qa"

test-lazyvim:
	nvim --headless -c "set rtp^=$$(pwd)" -c "luafile tests/parser_spec.lua" -c "qa"
	nvim --headless -c "set rtp^=$$(pwd)" -c "luafile tests/mappings_spec.lua" -c "qa"
