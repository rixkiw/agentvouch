import time, os, shutil
from playwright.sync_api import sync_playwright

OUT = "/home/ubuntu/hackathon/agentvouch/.demo"
shutil.rmtree(OUT, ignore_errors=True)
os.makedirs(OUT, exist_ok=True)
URL = "https://rixkiw.github.io/agentvouch/"

with sync_playwright() as p:
    ctx = p.chromium.launch_persistent_context(
        OUT + "/prof",
        headless=True,
        args=["--no-sandbox", "--disable-blink-features=AutomationControlled", "--force-device-scale-factor=1"],
        viewport={"width": 1280, "height": 720},
        record_video_dir=OUT + "/vid",
        record_video_size={"width": 1280, "height": 720},
        locale="en-US",
    )
    pg = ctx.pages[0] if ctx.pages else ctx.new_page()
    pg.goto(URL, wait_until="load", timeout=90000)
    pg.wait_for_timeout(6000)          # let the graph load
    # status + stats visible
    pg.wait_for_timeout(2000)

    # scroll to leaderboard
    pg.mouse.move(640, 400)
    for _ in range(6):
        pg.mouse.wheel(0, 220); pg.wait_for_timeout(350)
    pg.wait_for_timeout(3500)

    # scroll to the vouch builder
    pg.evaluate("document.getElementById('vouch').scrollIntoView({block:'start'})")
    pg.wait_for_timeout(2500)
    pg.click("#target")
    pg.keyboard.type("0x1bbD75de806bA32c1B2B3C29CbA16078D14A3356", delay=22)
    pg.click("#note")
    pg.keyboard.type("ships on time, contract verified, replied in 2h", delay=22)
    pg.wait_for_timeout(1200)
    pg.click("#build")
    pg.wait_for_timeout(3500)
    for _ in range(3):
        pg.mouse.wheel(0, 200); pg.wait_for_timeout(300)
    pg.wait_for_timeout(2500)

    # why agent id + disclosures
    pg.evaluate("window.scrollBy(0, 700)")
    pg.wait_for_timeout(3000)
    pg.evaluate("window.scrollBy(0, 700)")
    pg.wait_for_timeout(2500)
    pg.evaluate("window.scrollTo(0, document.body.scrollHeight)")
    pg.wait_for_timeout(3000)

    pg.close()
    ctx.close()

vids = [os.path.join(OUT + "/vid", f) for f in os.listdir(OUT + "/vid") if f.endswith(".webm")]
print("videos:", vids)
