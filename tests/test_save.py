"""The save game: CONTINUE with none stays on the main menu; S on the pause
screen writes ZPDATA/SAVEGAME.ZPS (the hardware build: /home/ZPSave/, made
at start-up: test_hardware.py runs this there too) and returns to the menu; CONTINUE on a
fresh start then brings back the level, weapons, stock, hit points,
salvage, booster, vision modes and vertical thrusters as they were.
"""
import os

import zptest as zp
from zptest import sym

LEVEL = 12


def state(cpu):
    R = cpu.rd
    return dict(level=R(sym["level"]), wave=R(sym["wave_number"]), salvage=cpu.rd16(sym["salvage_points"]),
                hp=R(sym["vtol_hp"]), slots=[(R(sym["wpn_slots"] + 2 * i), R(sym["wpn_slots"] + 2 * i + 1))
                                              for i in range(5)],
                sel=R(sym["wpn_sel"]), stock=[R(sym["wpn_stock"] + t) for t in range(sym["WPN_LAST"] + 1)],
                booster=(R(sym["boost_fitted"]), R(sym["boost_fuel"])),
                vision=R(sym["vision_owned"]), thrusters=R(sym["vthrust_fitted"]),
                lateral=R(sym["lthrust_fitted"]))


def save_path(sd):
    """Where the build writes the save game: the hardware build in
    /home/ZPSave on the card, the plain one in ZPDATA"""
    if "sg_home" in sym:
        return os.path.join(sd.root, "home", "ZPSave", "SAVEGAME.ZPS")
    return sd.path("SAVEGAME.ZPS")


def menu_scans(cpu, n, keys_at):
    """n scans of the main menu; keys_at: {scan number: keys}."""
    k = [0]

    def count():
        if zp.at_scan(cpu, sym["PAGE_MAINMENU"]):
            k[0] += 1
            cpu.keys = set(keys_at.get(k[0], ""))
        return k[0] >= n
    zp.run_until(cpu, count, "the main menu")


def test_continue_without_save():
    with zp.SD() as sd:
        cpu = zp.machine(sd)
        menu_scans(cpu, 6, {3: "2"})
        zp.check(cpu.mmu[6] == sym["PAGE_MAINMENU"], "CONTINUE without a save game left the main menu")


def test_save_and_continue():
    with zp.SD() as sd:
        cpu = zp.machine(sd)
        zp.start_game(cpu, LEVEL)
        W = sym["wpn_slots"]
        cpu.wr(W + 2, sym["WPN_ROCKETS"]); cpu.wr(W + 3, 5)
        cpu.wr(W + 4, sym["WPN_AUTOCANNON"]); cpu.wr(W + 5, 33)
        cpu.wr(sym["wpn_sel"], 1); cpu.wr(sym["vtol_hp"], 33); cpu.wr16(sym["salvage_points"], 37)
        cpu.wr(sym["boost_fitted"], 1); cpu.wr(sym["boost_fuel"], 120)
        cpu.wr(sym["vision_owned"], sym["VIS_NV_GREEN"] | sym["VIS_THERMAL"])
        cpu.wr(sym["vthrust_fitted"], 1)
        cpu.wr(sym["lthrust_fitted"], 1)
        cpu.wr(sym["wpn_stock"] + sym["WPN_MISSILE"], 2); cpu.wr(sym["wpn_unlocked"] + sym["WPN_MISSILE"], 1)
        zp.frames(cpu, 2)
        before = state(cpu)
        k = [0]

        def pause_then_s():
            if cpu.pc == sym["kbd_scan"]:
                k[0] += 1
                cpu.nextreg[0xB1] = 0x20 if k[0] == 1 else 0     # BREAK: pause
                cpu.keys = {"S"} if k[0] == 5 else set()
            return cpu.pc == sym["main_menu"] and cpu.mmu[6] == sym["PAGE_MAINMENU"]
        zp.run_until(cpu, pause_then_s, "the main menu after S")
        p = save_path(sd)
        zp.check(os.path.exists(p), f"{p} not written")
        cpu = zp.machine(sd)
        menu_scans(cpu, 3, {3: "2"})
        zp.run_until(cpu, lambda: cpu.pc == sym["main_loop"], "the game after CONTINUE")
        after = state(cpu)
        zp.check(after["level"] == LEVEL, f"CONTINUE started level {after['level']}, not {LEVEL}")
        zp.check(before == after, f"not as saved:\n        saved {before}\n        loaded {after}")


if __name__ == "__main__":
    zp.main(globals())
