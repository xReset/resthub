"""Execute the real loader with deterministic HTTP/hash/cache fakes.

Compilation and real SHA-256 checks are separate release-gate/network checks.
This suite verifies routing, dependency staging and failure ordering, not Roblox.
"""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
LUAU = ROOT.parent / "Potassium/tools/luau.exe"


def literal(value):
    if isinstance(value, dict):
        return "{" + ",".join(f"[{literal(k)}]={literal(v)}" for k, v in value.items()) + "}"
    if isinstance(value, list):
        return "{" + ",".join(map(literal, value)) + "}"
    if isinstance(value, str):
        return json.dumps(value)
    return str(value).lower()


HARNESS = r'''
local manifest = __MANIFEST__
local bodies, digests, cache, fetched = {}, {}, {}, {}
local cacheWrites, compiled, hubRan = 0, 0, false
local g = {}
for path,spec in pairs(manifest.files) do
    bodies[path] = "-- "..path
    digests[bodies[path]] = spec.sha256
end
local env = setmetatable({
    game = {GameId=969567031, PlaceId=120318126233314,
        GetService=function() return {JSONDecode=function() return manifest end} end},
    getgenv=function() return g end,
    task={wait=function() end, spawn=function() end},
    crypt={hash=function(body, algorithm)
        assert(algorithm=="sha256")
        return digests[body] or string.rep("0",64)
    end},
    httpget=function(url)
        if url:match("/main/manifest.json$") then return "manifest" end
        local prefix="https://raw.githubusercontent.com/xReset/resthub/"..manifest.revision.."/"
        assert(url:sub(1,#prefix)==prefix,"executable not fetched from immutable revision")
        local path=url:sub(#prefix+1)
        fetched[path]=true
        assert(bodies[path],"foreign or unknown file fetched: "..path)
        return bodies[path]
    end,
    readfile=function(path) assert(cache[path],"cache miss"); return cache[path] end,
    writefile=function(path,body)
        if path~="logs/resthub_loader.log" then
            cacheWrites+=1
            local required=3+(manifest.files["log.lua"] and 1 or 0)+(#manifest.modules>0 and 1 or 0)
            assert(compiled>=required,"cache changed before mandatory compilation")
            cache[path]=body
        end
    end,
    loadstring=function(body,name)
        assert(cacheWrites==0,"compilation after cache publication")
        compiled+=1
        return function()
            if name=="=resthub/hub.lua" then
                if manifest.files["log.lua"] then assert(cache["log.lua"]) end
                hubRan=true
            end
        end
    end,
}, {__index=getfenv()})
__SETUP__
local function loader()
__LOADER__
end
setfenv(loader,env)
local ok,err=pcall(loader)
__ASSERT__
'''


class LoaderTests(unittest.TestCase):
    def run_loader(self, setup, assertions):
        manifest = json.loads((ROOT / "manifest.json").read_text())
        manifest["revision"] = "a" * 40
        script = (HARNESS.replace("__MANIFEST__", literal(manifest))
                  .replace("__SETUP__", setup)
                  .replace("__ASSERT__", assertions)
                  .replace("__LOADER__", (ROOT / "loader.lua").read_text()))
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "loader_test.luau"
            path.write_text(script)
            result = subprocess.run([str(LUAU), str(path)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_fresh_install_stages_logger_and_only_matching_module(self):
        self.run_loader("", '''
assert(ok,err)
assert(hubRan and g.__RESTHUB_LOADER.module=="bizarre-day-classic")
assert(cache["log.lua"] and cache["abd_item_esp.lua"])
assert(fetched["games/abd_item_esp.lua"])
for _,m in ipairs(manifest.modules) do
    if m.id~="bizarre-day-classic" then assert(not fetched[m.path]) end
end
''')

    def test_universe_match_routes_other_places_in_same_game(self):
        self.run_loader("env.game.PlaceId=1", 'assert(ok,err); assert(hubRan and fetched["games/abd_item_esp.lua"])')

    def test_wideopen_routes_only_its_verified_module(self):
        for place in (109959833715820, 1):
            with self.subTest(place=place):
                self.run_loader(f'env.game.GameId=10766812776; env.game.PlaceId={place}', '''
assert(ok,err)
assert(hubRan and g.__RESTHUB_LOADER.module=="wideopen")
assert(cache["log.lua"] and cache["wideopen_hub.lua"])
assert(fetched["games/wideopen_hub.lua"])
for _,m in ipairs(manifest.modules) do
    if m.id~="wideopen" then assert(not fetched[m.path]) end
end
''')

    def test_corrupt_wideopen_does_not_publish_or_run(self):
        self.run_loader('''
env.game.GameId=10766812776; env.game.PlaceId=109959833715820
bodies["games/wideopen_hub.lua"]="corrupt"
''', '''
assert(not ok and tostring(err):find("SHA%-256 mismatch"))
assert(cacheWrites==0 and not hubRan)
assert(g.__RESTHUB_LOADER.running==false)
''')

    def test_new_game_modules_route_by_universe_only(self):
        cases = [
            ("clover-rpg", 3164482049, (8248288152, 8248164019, 1), "clover_hub.lua"),
            ("bike-universe", 10768284407, (98628861455414, 1), "bike_universe_hub.lua"),
            ("backseat-rally", 10769543742, (94278659624110, 1), "backseat_rally_hub.lua"),
        ]
        for module, universe, places, filename in cases:
            for place in places:
                with self.subTest(module=module, place=place):
                    self.run_loader(f'env.game.GameId={universe}; env.game.PlaceId={place}', f'''
assert(ok,err)
assert(hubRan and g.__RESTHUB_LOADER.module=="{module}")
assert(cache["log.lua"] and cache["{filename}"])
assert(fetched["games/{filename}"])
for _,m in ipairs(manifest.modules) do
    if m.id~="{module}" then assert(not fetched[m.path]) end
end
''')

    def test_foreign_universe_cannot_route_by_matching_clover_place(self):
        self.run_loader('env.game.GameId=1; env.game.PlaceId=8248288152', '''
assert(ok,err)
assert(hubRan and g.__RESTHUB_LOADER.module=="none")
for _,m in ipairs(manifest.modules) do assert(not fetched[m.path]) end
''')

    def test_corrupt_clover_does_not_publish_or_run(self):
        self.run_loader('''
env.game.GameId=3164482049; env.game.PlaceId=8248288152
bodies["games/clover_hub.lua"]="corrupt"
''', '''
assert(not ok and tostring(err):find("SHA%-256 mismatch"))
assert(cacheWrites==0 and not hubRan)
assert(g.__RESTHUB_LOADER.running==false)
''')

    def test_corrupt_required_logger_does_not_publish_or_run(self):
        self.run_loader('bodies["log.lua"]="corrupt"', '''
assert(not ok and tostring(err):find("SHA%-256 mismatch"))
assert(cacheWrites==0 and not hubRan)
assert(g.__RESTHUB_LOADER.running==false)
''')

    def test_older_release_without_shared_logger_still_boots(self):
        self.run_loader('''
manifest.minLoader=3
manifest.files["log.lua"]=nil
manifest.modules={}
''', 'assert(ok,err); assert(hubRan and not fetched["log.lua"])')


if __name__ == "__main__":
    unittest.main()
