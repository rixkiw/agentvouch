import time, os, shutil
from playwright.sync_api import sync_playwright

OUT = "/home/ubuntu/hackathon/agentvouch/.demo2"
shutil.rmtree(OUT, ignore_errors=True)
os.makedirs(OUT, exist_ok=True)

with sync_playwright() as p:
    ctx = p.chromium.launch_persistent_context(
        OUT + "/prof", headless=True,
        args=["--no-sandbox", "--disable-blink-features=AutomationControlled", "--force-device-scale-factor=1"],
        viewport={"width": 1280, "height": 720},
        record_video_dir=OUT + "/vid",
        record_video_size={"width": 1280, "height": 720},
        locale="en-US",
    )
    pg = ctx.pages[0] if ctx.pages else ctx.new_page()
    pg.goto("https://rixkiw.github.io/agentvouch/proof.html", wait_until="load", timeout=90000)
    pg.wait_for_timeout(9000)
    pg.mouse.move(640, 300)
    for _ in range(3):
        pg.mouse.wheel(0, 180); pg.wait_for_timeout(500)
    pg.wait_for_timeout(4000)
    pg.evaluate("window.scrollTo(0, document.body.scrollHeight)")
    pg.wait_for_timeout(4500)
    pg.close(); ctx.close()

print([f for f in os.listdir(OUT + "/vid")])
