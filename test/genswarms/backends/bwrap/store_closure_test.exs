defmodule Genswarms.Backends.Bwrap.StoreClosureTest do
  use ExUnit.Case, async: true
  alias Genswarms.Backends.Bwrap.StoreClosure

  describe "parse_requisites/1" do
    test "splits newline-separated store paths" do
      out = "/nix/store/aaa-bash\n/nix/store/bbb-glibc\n"
      assert {:ok, ["/nix/store/aaa-bash", "/nix/store/bbb-glibc"]} =
               StoreClosure.parse_requisites(out)
    end

    test "rejects empty output" do
      assert {:error, :empty_closure} = StoreClosure.parse_requisites("\n  \n")
    end

    test "rejects a non-store line" do
      assert {:error, {:non_store_path, "/usr/bin/whoops"}} =
               StoreClosure.parse_requisites("/nix/store/aaa-bash\n/usr/bin/whoops\n")
    end
  end

  describe "store_root/1 and parse_ldd/1" do
    test "store_root reduces a file path to its /nix/store/<hash>-name root" do
      assert StoreClosure.store_root("/nix/store/h-glibc-2.40/lib/ld-linux.so.2") ==
               "/nix/store/h-glibc-2.40"
    end

    test "parse_ldd extracts uniq store roots from ldd output" do
      ldd = """
              linux-vdso.so.1 (0x00007fff...)
              libcjson.so.1 => /nix/store/h-cjson-1.7/lib/libcjson.so.1 (0x00007f...)
              libc.so.6 => /nix/store/h-glibc-2.40/lib/libc.so.6 (0x00007f...)
              /nix/store/h-glibc-2.40/lib/ld-linux-x86-64.so.2 (0x00007f...)
      """

      assert StoreClosure.parse_ldd(ldd) == ["/nix/store/h-cjson-1.7", "/nix/store/h-glibc-2.40"]
    end
  end

  describe "paths_to_binds/1" do
    test "emits one --ro-bind <p> <p> per path" do
      assert StoreClosure.paths_to_binds(["/nix/store/a", "/nix/store/b"]) ==
               ["--ro-bind", "/nix/store/a", "/nix/store/a",
                "--ro-bind", "/nix/store/b", "/nix/store/b"]
    end
  end
end
