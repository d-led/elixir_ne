# Pythonx embeds a CPython interpreter; its tests run where an interpreter is
# wanted: mix test --include pythonx
ExUnit.start(exclude: [:pythonx])
