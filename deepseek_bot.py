from aiogram import Bot, Dispatcher, types, F
from aiogram.types import InlineKeyboardMarkup, InlineKeyboardButton
import asyncio

API_TOKEN = "8122344056:AAH_nPl7TLvP2QqcOJKW-lrqw5aRi0I8YzA"
ADMINS = {6961049578, 123456789}

bot = Bot(token=API_TOKEN)
dp = Dispatcher()

star_price = {"value": 0.40}
user_balances = {}
banned_users = set()
all_users = set()

# Esasy menýu knopkasy
def get_main_menu():
    return InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="💲 Baha", callback_data="show_price")],
        [InlineKeyboardButton(text="🧮 Hasapla", callback_data="enter_star")],
        [InlineKeyboardButton(text="🛒 Satyn al", callback_data="buy")],
    ])

# Admin paneli
def get_admin_panel(user_id):
    return InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="➕ 50 star", callback_data=f"add_{user_id}_50"),
         InlineKeyboardButton(text="➖ 50 star", callback_data=f"remove_{user_id}_50")],
        [InlineKeyboardButton(text="⛔ Ban", callback_data=f"ban_{user_id}"),
         InlineKeyboardButton(text="✅ Unban", callback_data=f"unban_{user_id}")],
        [InlineKeyboardButton(text="💲 Bahany üýtget", callback_data="change_price")]
    ])

# Baha saýlamak knopkasy (admin üçin)
def get_price_buttons():
    return InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="0.30 TMT", callback_data="set_0.30")],
        [InlineKeyboardButton(text="0.35 TMT", callback_data="set_0.35")],
        [InlineKeyboardButton(text="0.40 TMT", callback_data="set_0.40")],
        [InlineKeyboardButton(text="0.45 TMT", callback_data="set_0.45")],
        [InlineKeyboardButton(text="0.50 TMT", callback_data="set_0.50")],
    ])

# Start
@dp.message(F.text)
async def handle_start(message: types.Message):
    user_id = message.from_user.id
    all_users.add(user_id)

    if user_id in banned_users:
        await message.answer("⛔ Siziň akkauntyňyz gadagan edildi.")
        return

    if user_id not in user_balances:
        user_balances[user_id] = 0

    await message.answer(
        f"👋 Hoş geldiňiz STAR BOT-a!\n"
        f"Bot arkaly staryňyzy hasaplap, satyn alyp bilersiňiz.\n\n"
        f"🧮 Häzirki baha: {star_price['value']} TMT\n"
        f"💼 Siziň hasabyňyz: {user_balances[user_id]} star",
        reply_markup=get_main_menu()
    )

    if user_id in ADMINS:
        await message.answer("🔧 Admin paneli", reply_markup=get_admin_panel(user_id))

# Button: baha görkez
@dp.callback_query(F.data == "show_price")
async def show_price(callback: types.CallbackQuery):
    await callback.message.edit_text(
        f"📌 Häzirki baha: 1 star = {star_price['value']} TMT",
        reply_markup=get_main_menu()
    )
    await callback.answer()

# Button: baha üýtget
@dp.callback_query(F.data == "change_price")
async def change_price(callback: types.CallbackQuery):
    if callback.from_user.id in ADMINS:
        await callback.message.edit_text("Täze baha saýla:", reply_markup=get_price_buttons())
    await callback.answer()

# Baha täzeden saýlamak
@dp.callback_query(F.data.startswith("set_"))
async def set_price(callback: types.CallbackQuery):
    if callback.from_user.id not in ADMINS:
        await callback.answer("⛔ Diňe admin baha üýtgedip biler.", show_alert=True)
        return
    new_price = float(callback.data.split("_")[1])
    star_price["value"] = new_price
    await callback.message.edit_text(f"✅ Täze baha goýuldy: 1 star = {new_price} TMT", reply_markup=get_main_menu())
    await callback.answer("Baha täzelendi ✅")

# Button: hasapla
@dp.callback_query(F.data == "enter_star")
async def prompt_star_amount(callback: types.CallbackQuery):
    await callback.message.edit_text("📥 Staryňyzyň sanyny ýazyň (mysal: 150):")
    await callback.answer()

# Ulanyjy san girizse
@dp.message(F.text.regexp(r'^\d+$'))
async def handle_amount(message: types.Message):
    stars = int(message.text)
    tmt = stars * star_price["value"]
    await message.answer(
        f"⭐️ {stars} star × {star_price['value']} TMT = {tmt:.2f} TMT"
    )

# Button: satyn al
@dp.callback_query(F.data == "buy")
async def buy_menu(callback: types.CallbackQuery):
    p = star_price["value"]
    keyboard = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text=f"50 star - {50*p:.2f} TMT", callback_data="buy_50")],
        [InlineKeyboardButton(text=f"100 star - {100*p:.2f} TMT", callback_data="buy_100")],
        [InlineKeyboardButton(text=f"250 star - {250*p:.2f} TMT", callback_data="buy_250")],
        [InlineKeyboardButton(text=f"500 star - {500*p:.2f} TMT", callback_data="buy_500")],
    ])
    await callback.message.edit_text("🛒 Satyn almak üçin mukdary saýlaň:", reply_markup=keyboard)
    await callback.answer()

# Sargytlar
@dp.callback_query(F.data.startswith("buy_"))
async def handle_buy(callback: types.CallbackQuery):
    amount = int(callback.data.split("_")[1])
    total = amount * star_price["value"]
    user = callback.from_user

    await callback.message.edit_text(
        f"✅ Siz {amount} star satyn almak isleýärsiňiz.\n"
        f"💵 Bahasy: {total:.2f} TMT\n"
        f"📸 Töleg skrinshotyny admina ugratmaly.\n"
        f"📨 Admin: @username"
    )
    await callback.answer()

    for admin in ADMINS:
        await bot.send_message(
            admin,
            f"🛒 Täze sargyt:\n👤 @{user.username or user.first_name}\n🆔 {user.id}\n📦 {amount} star\n💳 {total:.2f} TMT"
        )

# Admin ➕➖
@dp.callback_query(F.data.startswith("add_"))
async def admin_add(callback: types.CallbackQuery):
    if callback.from_user.id in ADMINS:
        _, uid, amount = callback.data.split("_")
        uid = int(uid)
        amount = int(amount)
        user_balances[uid] = user_balances.get(uid, 0) + amount
        await callback.answer(f"{amount} star goşuldy ✅")

@dp.callback_query(F.data.startswith("remove_"))
async def admin_remove(callback: types.CallbackQuery):
    if callback.from_user.id in ADMINS:
        _, uid, amount = callback.data.split("_")
        uid = int(uid)
        amount = int(amount)
        user_balances[uid] = max(user_balances.get(uid, 0) - amount, 0)
        await callback.answer(f"{amount} star aýyryldy ✅")

# Ban / Unban
@dp.callback_query(F.data.startswith("ban_"))
async def ban_user(callback: types.CallbackQuery):
    if callback.from_user.id in ADMINS:
        uid = int(callback.data.split("_")[1])
        banned_users.add(uid)
        await callback.answer("Ulanyjy ban edildi ⛔")

@dp.callback_query(F.data.startswith("unban_"))
async def unban_user(callback: types.CallbackQuery):
    if callback.from_user.id in ADMINS:
        uid = int(callback.data.split("_")[1])
        banned_users.discard(uid)
        await callback.answer("Ulanyjy unban edildi ✅")

# Başlatmak
async def main():
    print("🤖 STAR BOT başlady...")
    await dp.start_polling(bot)

if __name__ == "__main__":
    asyncio.run(main())