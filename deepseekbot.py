# STAR BOT
from aiogram import Bot, Dispatcher, types, F
from aiogram.filters import CommandStart, Command
from aiogram.types import InlineKeyboardMarkup, InlineKeyboardButton
import asyncio

API_TOKEN = "7900360043:AAGr7yOAcWPUN03a8Fta4SOh8mEuJa-917k"
ADMINS = {6961049578, 123456789}  # Admin ID-ler

bot = Bot(token=API_TOKEN)
dp = Dispatcher()

star_price = {"value": 0.40}
user_balances = {}
banned_users = set()
all_users = set()

# Baha saýlaýan knopkalar
def get_price_buttons():
    return InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="0.30 TMT", callback_data="set_0.30")],
        [InlineKeyboardButton(text="0.35 TMT", callback_data="set_0.35")],
        [InlineKeyboardButton(text="0.40 TMT", callback_data="set_0.40")],
        [InlineKeyboardButton(text="0.45 TMT", callback_data="set_0.45")],
        [InlineKeyboardButton(text="0.50 TMT", callback_data="set_0.50")]
    ])

# Admin panel knopkasy
def get_admin_panel(user_id):
    return InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="➕ 50 star", callback_data=f"add_{user_id}_50"),
         InlineKeyboardButton(text="➖ 50 star", callback_data=f"remove_{user_id}_50")],
        [InlineKeyboardButton(text="⛔ Ban", callback_data=f"ban_{user_id}"),
         InlineKeyboardButton(text="✅ Unban", callback_data=f"unban_{user_id}")]
    ])

# /start buýrugy
@dp.message(CommandStart())
async def start_cmd(message: types.Message):
    user_id = message.from_user.id
    all_users.add(user_id)

    if user_id in banned_users:
        await message.answer("⛔ Siziň akkauntyňyz gadagan edildi.")
        return

    if user_id not in user_balances:
        user_balances[user_id] = 0

    await message.answer(
        f"👋 Hoş geldiňiz!\n\n"
        f"Bu bot Telegram Stars → TMT baha hasaplaýar we satyn alyp bolýar.\n"
        f"Staryňyzyň sanyny giriziň ýa-da /buy komandasyny ulanyň.\n\n"
        f"🧮 Häzirki baha: 1 star = {star_price['value']} TMT\n"
        f"💼 Hasap: {user_balances[user_id]} star"
    )

    if user_id in ADMINS:
        await message.answer("🔧 Admin panel:", reply_markup=get_admin_panel(user_id))

# /price
@dp.message(Command("price"))
async def show_price(message: types.Message):
    await message.answer(f"📌 Häzirki baha: 1 star = {star_price['value']} TMT")

# /setprice
@dp.message(Command("setprice"))
async def set_price_cmd(message: types.Message):
    if message.from_user.id in ADMINS:
        await message.answer("💲 Täze baha saýlaň:", reply_markup=get_price_buttons())
    else:
        await message.answer("⛔ Bu buýruk diňe admin üçin.")

# /broadcast
@dp.message(Command("broadcast"))
async def broadcast(message: types.Message):
    if message.from_user.id not in ADMINS:
        return
    args = message.text.split(maxsplit=1)
    if len(args) < 2:
        await message.answer("✉️ Habar tekstini ýazmaly: /broadcast salam")
        return
    sent = 0
    for user_id in all_users:
        try:
            await bot.send_message(user_id, args[1])
            sent += 1
        except:
            pass
    await message.answer(f"✅ Ugratdyk: {sent} ulanyja")

# Baha üýtgetmek
@dp.callback_query(F.data.startswith("set_"))
async def change_price(callback: types.CallbackQuery):
    if callback.from_user.id not in ADMINS:
        await callback.answer("⛔ Diňe admin baha üýtgedip biler.", show_alert=True)
        return
    new_price = float(callback.data.split("_")[1])
    star_price["value"] = new_price
    await callback.message.edit_text(f"✅ Täze baha goýuldy: 1 star = {new_price} TMT")
    await callback.answer("Baha täzelendi ✅")

# Admin ➕
@dp.callback_query(F.data.startswith("add_"))
async def admin_add(callback: types.CallbackQuery):
    if callback.from_user.id not in ADMINS:
        return
    _, uid, amount = callback.data.split("_")
    uid = int(uid)
    amount = int(amount)
    user_balances[uid] = user_balances.get(uid, 0) + amount
    await callback.answer(f"{amount} star goşuldy ✅")

# Admin ➖
@dp.callback_query(F.data.startswith("remove_"))
async def admin_remove(callback: types.CallbackQuery):
    if callback.from_user.id not in ADMINS:
        return
    _, uid, amount = callback.data.split("_")
    uid = int(uid)
    amount = int(amount)
    user_balances[uid] = max(user_balances.get(uid, 0) - amount, 0)
    await callback.answer(f"{amount} star aýyryldy ✅")

# Ban/Unban
@dp.callback_query(F.data.startswith("ban_"))
async def admin_ban(callback: types.CallbackQuery):
    if callback.from_user.id not in ADMINS:
        return
    _, uid = callback.data.split("_")
    banned_users.add(int(uid))
    await callback.answer("Ulanyjy ban edildi ⛔")

@dp.callback_query(F.data.startswith("unban_"))
async def admin_unban(callback: types.CallbackQuery):
    if callback.from_user.id not in ADMINS:
        return
    _, uid = callback.data.split("_")
    banned_users.discard(int(uid))
    await callback.answer("Ulanyjy unban edildi ✅")

# Staryňy girizeninde hasapla
@dp.message(F.text.regexp(r'^\d+$'))
async def calculate(message: types.Message):
    if message.from_user.id in banned_users:
        await message.answer("⛔ Siziň akkauntyňyz gadagan edildi.")
        return
    stars = int(message.text)
    tmt = stars * star_price["value"]
    await message.answer(
        f"⭐️ Staryňyz: {stars} star\n"
        f"💵 Bahasy: {tmt:.2f} TMT\n"
        f"(1 star = {star_price['value']} TMT)"
    )

# /buy
@dp.message(Command("buy"))
async def buy_stars(message: types.Message):
    if message.from_user.id in banned_users:
        await message.answer("⛔ Siziň akkauntyňyz gadagan edildi.")
        return
    price = star_price["value"]
    keyboard = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text=f"50 star - {50 * price:.2f} TMT", callback_data="buy_50")],
        [InlineKeyboardButton(text=f"100 star - {100 * price:.2f} TMT", callback_data="buy_100")],
        [InlineKeyboardButton(text=f"250 star - {250 * price:.2f} TMT", callback_data="buy_250")],
        [InlineKeyboardButton(text=f"500 star - {500 * price:.2f} TMT", callback_data="buy_500")]
    ])
    await message.answer("🛒 Satyn almak üçin staryň mukdaryny saýlaň:", reply_markup=keyboard)

# Sargyt işle
@dp.callback_query(F.data.startswith("buy_"))
async def handle_buy(callback: types.CallbackQuery):
    amount = int(callback.data.split("_")[1])
    total_price = amount * star_price["value"]
    user = callback.from_user

    await callback.message.edit_text(
        f"✅ Siz {amount} star satyn almak isleýärsiňiz.\n"
        f"💵 Bahasy: {total_price:.2f} TMT\n"
        f"📸 Töleg skrinshotyny admine ugratmak gerek.\n"
        f"📨 Töleg üçin habarlaşyň: @username"
    )
    await callback.answer("Sargyt ugradyldy ✅")

    for admin in ADMINS:
        await bot.send_message(
            chat_id=admin,
            text=(
                f"🛒 Täze sargyt:\n"
                f"👤 Ulanyjy: @{user.username or user.first_name}\n"
                f"🆔 ID: {user.id}\n"
                f"📦 Mukdar: {amount} star\n"
                f"💳 Töleg: {total_price:.2f} TMT"
            )
        )

# Nädogry tekst girizse
@dp.message()
async def invalid(message: types.Message):
    await message.answer("📥 Diňe staryňyzyň sanyny giriziň (mysal: 150)")

# Başlatmak
async def main():
    print("🤖 Bot başlady...")
    await dp.start_polling(bot)

if __name__ == "__main__":
    asyncio.run(main())