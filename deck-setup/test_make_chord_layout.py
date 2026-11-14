#!/usr/bin/env python3
# Tests for make-chord-layout.py: python3 deck-setup/test_make_chord_layout.py
import importlib.util, os, re, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("mcl", os.path.join(HERE, "make-chord-layout.py"))
mcl = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mcl)

# A cut-down layout in Steam's format: one switches group with two grips set by hand (one with an
# editor-disabled activator), a trackpad group that must stay untouched, and the default preset.
SAMPLE = '''"controller_mappings"
{
	"version"		"3"
	"title"		"Test layout"
	"group"
	{
		"id"		"7"
		"mode"		"switches"
		"inputs"
		{
			"button_escape"
			{
				"activators"
				{
					"Full_Press"
					{
						"bindings"
						{
							"binding"		"xinput_button START"
						}
					}
				}
			}
			"button_back_left_upper"
			{
				"activators"
				{
					"Full_Press"
					{
						"bindings"
						{
							"binding"		"key_press F8"
						}
					}
					"Double_Press"
					{
						"bindings"
						{
							"binding"		"key_press Q, , "
						}
					}
				}
				"disabled_activators"
				{
					"Long_Press"		"1"
				}
			}
			"button_back_right"
			{
				"activators"
				{
				}
			}
		}
	}
	"group"
	{
		"id"		"13"
		"mode"		"mouse_joystick"
		"inputs"
		{
			"click"
			{
				"activators"
				{
					"Soft_Press"
					{
						"bindings"
						{
							"binding"		"xinput_button JOYSTICK_RIGHT"
						}
					}
				}
			}
		}
	}
	"preset"
	{
		"id"		"0"
		"name"		"Default"
		"group_source_bindings"
		{
			"7"		"switch active"
			"13"		"right_trackpad active"
		}
	}
}
'''

HOLD = {"L4": 400, "R4": 400, "L5": 400, "R5": 400}


def grip(root, steam_input):
    layout = root[0][1]
    for g in mcl.get_all(layout, "group"):
        inputs = mcl.get(g, "inputs") or []
        e = mcl.get(inputs, steam_input)
        if e is not None:
            return e


def bindings(activator):
    return [p[1] for p in mcl.get(activator, "bindings") if p[0] == "binding"]


class Tests(unittest.TestCase):
    def test_round_trip_is_exact(self):
        self.assertEqual(mcl.dump(mcl.parse(SAMPLE)), SAMPLE)

    def test_every_grip_gets_two_plain_keys(self):
        root = mcl.parse(mcl.apply(SAMPLE, HOLD))
        for name, steam_input, key, long_key in mcl.GRIPS:
            acts = mcl.get(grip(root, steam_input), "activators")
            self.assertEqual([p[0] for p in acts], ["Full_Press", "Long_Press"], name)
            full, long_ = mcl.get(acts, "Full_Press"), mcl.get(acts, "Long_Press")
            self.assertEqual(bindings(full), ["key_press %s, , " % key])
            self.assertEqual(mcl.get(mcl.get(full, "settings"), "interruptable"), "0")
            self.assertEqual(bindings(long_), ["key_press %s, , " % long_key])
            self.assertEqual(mcl.get(mcl.get(long_, "settings"), "long_press_time"), "400")

    def test_each_key_appears_once(self):
        out = mcl.apply(SAMPLE, HOLD)
        for _, _, key, long_key in mcl.GRIPS:
            self.assertEqual(out.count('"key_press %s, , "' % key), 1, key)
            self.assertEqual(out.count('"key_press %s, , "' % long_key), 1, long_key)

    def test_keys_match_the_addon(self):
        core = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "addons", "DeckKit", "Core.lua")).read()
        lua = re.findall(r'\{ name = "(\w+)", key = "(\w+)", long = "(\w+)" \}', core)
        self.assertEqual(lua, [(name, key, long_key) for name, _, key, long_key in mcl.GRIPS])

    def test_disabled_activators_are_cleared(self):
        root = mcl.parse(mcl.apply(SAMPLE, HOLD))
        self.assertEqual(mcl.get(grip(root, "button_back_left_upper"), "disabled_activators"), [])

    def test_hold_time_per_grip(self):
        root = mcl.parse(mcl.apply(SAMPLE, dict(HOLD, R5=650)))
        acts = mcl.get(grip(root, "button_back_right"), "activators")
        self.assertEqual(mcl.get(mcl.get(mcl.get(acts, "Long_Press"), "settings"), "long_press_time"), "650")

    def test_everything_else_untouched(self):
        before, after = mcl.parse(SAMPLE), mcl.parse(mcl.apply(SAMPLE, HOLD))
        self.assertEqual(grip(before, "button_escape"), grip(after, "button_escape"))
        self.assertEqual(grip(before, "click"), grip(after, "click"))
        self.assertEqual(mcl.get_all(before[0][1], "preset"), mcl.get_all(after[0][1], "preset"))

    def test_applying_twice_changes_nothing(self):
        once = mcl.apply(SAMPLE, HOLD)
        self.assertEqual(mcl.apply(once, HOLD), once)

    def test_finds_forever_layouts_only(self):
        import tempfile
        with tempfile.TemporaryDirectory() as root:
            def layout(account, game):
                d = os.path.join(root, account, "config", game)
                os.makedirs(d)
                open(os.path.join(d, "controller_neptune.vdf"), "w").write(SAMPLE)
            layout("111", "wow forever")
            layout("111", "some other game")
            layout("222", "WoW Forever (Lutris)")
            old, mcl.CONFIGS = mcl.CONFIGS, root
            try:
                found = mcl.find_layouts()
                self.assertEqual(len(found), 2)
                self.assertTrue(all("orever" in f for f in found))
                self.assertEqual(len(mcl.find_layouts("some other game")), 1)
                # With nothing matching, the folders that are there get listed, each once.
                self.assertEqual(mcl.layout_folders(), ["WoW Forever (Lutris)", "some other game", "wow forever"])
            finally:
                mcl.CONFIGS = old

    def test_rejects_other_files(self):
        with self.assertRaises(ValueError):
            mcl.apply('"something"\n{\n}\n', HOLD)


if __name__ == "__main__":
    unittest.main()
