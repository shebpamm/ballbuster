.PHONY: build run

build:
	godot --headless --export-release "Linux" game/project.godot

run: build
	steam-run ./build.x86_64
