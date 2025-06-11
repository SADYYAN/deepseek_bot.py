from aiogram import Bot, Dispatcher, F
from aiogram.types import Message, InlineKeyboardButton, InlineKeyboardMarkup
from aiogram.enums import ParseMode
from aiogram.filters import CommandStart
import asyncio

BOT_TOKEN = "7997369018:AAEj_4EILhIg9mo0KGUm2zbIEoRqwwsWQ_U"  # Bu ýere öz bot tokeniňi giriz

bot = Bot(token=BOT_TOKEN, parse_mode=ParseMode.HTML)
dp = Dispatcher()

# Nakrutka hyzmatlarynyň düwme menyusy
def get_services_keyboard():
    keyboard = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text="👍 Лайки", callback_data="likes")],
        [InlineKeyboardButton(text="👁 Просмотры", callback_data="views")],
        [InlineKeyboardButton(text="👥 Подписчики", callback_data="subs")],
    ])
    return keyboard

# Start komandasy üçin
@dp.message(CommandStart())
async def cmd_start(message: Message):
    # Ulanyjyny gerekli linke geçirmäge mejbur edýäs
    await message.answer(
        "❗ Для использования бота перейдите по ссылке и нажмите старт:\n"
        "<a href='https://t.me/aybotstar_bot?start=6961049578'>Нажмите здесь</a>\n\n"
        "После этого выберите нужную услугу 👇",
        reply_markup=get_services_keyboard()
    )

# Callback-lar bilen işleýän funksiýa
@dp.callback_query()
async def handle_callback(callback_query):
    data = callback_query.data
    if data == "likes":
        await callback_query.message.answer("🟢 Вы выбрали: Лайки")
    elif data == "views":
        await callback_query.message.answer("🟢 Вы выбрали: Просмотры")
    elif data == "subs":
        await callback_query.message.answer("🟢 Вы выбрали: Подписчики")

# Boty işledýäris
async def main():
    await dp.start_polling(bot)

if __name__ == "__main__":
    asyncio.run(main())