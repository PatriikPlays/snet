-- janky
shell.run("cd howl")
shell.run("./bootstrap.lua")
assert(fs.exists(shell.resolve("./build/Howl.lua")))
shell.run("cd ..")
shell.run("./howl/build/Howl.lua build")
