## Instance a bot, run one query against Enu's VM, print the answer.
import client, models/bots

Enu.client.connect

let bot = Bot.init(0, 0, -150)
Enu.units.add bot

echo "1 + 1 = ", bot.eval("1 + 1")
