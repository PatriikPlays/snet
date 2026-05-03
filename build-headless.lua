-- janky
shell.run("cd howl")
shell.run("./bootstrap.lua")
if not fs.exists(shell.resolve("./build/Howl.lua")) then
    os.shutdown(1)
end
shell.run("cd ..")
shell.run("./howl/build/Howl.lua build")

os.shutdown(0)
