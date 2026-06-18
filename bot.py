import os
import time
import asyncio
import discord
from discord.ext import commands, tasks
from dotenv import load_dotenv
from event_schedule import get_cycle_info, get_deterministic_event, cycle_active_start, COOLDOWN_SEC

load_dotenv()

EVENT_CHANNEL_ID = int(os.getenv("EVENT_CHANNEL_ID"))
EVENT_ROLE_ID = int(os.getenv("EVENT_ROLE_ID"))

EVENT_COLORS = {
    "Silver": 0xC0C0C0,
    "Taco": 0xF4A460,
    "Alien": 0x7CFC00,
    "Gold": 0xFFD700,
    "Diamond": 0x00BFFF,
    "Ruby": 0xDC143C,
    "Galaxy": 0x8A2BE2,
    "Aquatic": 0x00CED1,
    "Black Hole": 0x1C1C1C,
}

bot = commands.Bot(command_prefix="!", intents=discord.Intents.default())
last_starting_soon_cycle = -1
last_active_cycle = -1


@bot.event
async def on_ready():
    print(f"{bot.user} is online!")
    try:
        synced = await bot.tree.sync()
        print(f"Synced {len(synced)} slash command(s)")
    except Exception as e:
        print(f"Failed to sync commands: {e}")
    if not event_loop.is_running():
        event_loop.start()


@tasks.loop(seconds=5)
async def event_loop():
    global last_starting_soon_cycle, last_active_cycle

    now = int(time.time())
    cycle_index, event, phase, sec_left = get_cycle_info(now)
    channel = bot.get_channel(EVENT_CHANNEL_ID)
    if not channel:
        return

    color = EVENT_COLORS.get(event, 0x808080)
    role_mention = f"<@&{EVENT_ROLE_ID}>"

    if phase == "cooldown" and cycle_index != last_starting_soon_cycle:
        last_starting_soon_cycle = cycle_index
        embed = discord.Embed(
            title=f"{event} Event is starting soon!",
            description=f"The **{event}** event will begin in a few moments. Get ready!",
            color=color,
        )
        content = role_mention if event in ("Aquatic", "Black Hole") else None
        await channel.send(content=content, embed=embed)

    if phase == "active" and cycle_index != last_active_cycle:
        last_active_cycle = cycle_index
        embed = discord.Embed(
            title=f"{event} Event is ACTIVE!",
            description=f"The **{event}** event has started! Jump in now to participate.",
            color=color,
        )
        await channel.send(embed=embed)


@bot.tree.command(name="ping", description="Check if the bot is alive")
async def ping(interaction: discord.Interaction):
    await interaction.response.send_message(f"Pong! Latency: {round(bot.latency * 1000)}ms")


@bot.tree.command(name="event", description="Check the current event status")
async def event_cmd(interaction: discord.Interaction):
    now = int(time.time())
    cycle_index, event, phase, sec_left = get_cycle_info(now)
    color = EVENT_COLORS.get(event, 0x808080)

    if phase == "active":
        minutes, seconds = divmod(sec_left, 60)
        embed = discord.Embed(
            title=f"{event} Event is ACTIVE!",
            description=f"Ends in **{minutes}m {seconds}s**",
            color=color,
        )
    else:
        minutes, seconds = divmod(sec_left, 60)
        embed = discord.Embed(
            title=f"Next Event: {event}",
            description=f"Starts in **{minutes}m {seconds}s**",
            color=color,
        )

    next_events = []
    for i in range(5):
        idx = cycle_index + i + 1
        ev = get_deterministic_event(idx)
        start_ts = cycle_active_start(idx)
        next_events.append(f"<t:{start_ts}:R> - **{ev}**")

    embed.add_field(name="Upcoming Events", value="\n".join(next_events), inline=False)
    await interaction.response.send_message(embed=embed)


bot.run(os.getenv("DISCORD_TOKEN"))
