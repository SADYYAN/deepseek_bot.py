import os
import zipfile
import logging
import asyncio
import aiosqlite
from datetime import datetime, timedelta
from aiogram import Bot, Dispatcher
from aiogram.types import InlineKeyboardMarkup, InlineKeyboardButton
from aiogram.middlewares.logging import LoggingMiddleware  # Update for Aiogram 3.x
from aiogram.fsm.context import FSMContext
from aiogram.fsm.state import State, StatesGroup
from aiogram.fsm.storage.memory import MemoryStorage

TOKEN = '7928329417:AAG2dO_6DjHelwjkfYmy_Pf7-57abMIUVtM'
ADMIN = [8165866779]
DB = 'backup.db'

bot = Bot(token=TOKEN)
dp = Dispatcher(bot, storage=MemoryStorage())
dp.middleware.setup(LoggingMiddleware())

backup_task_status = {'running': True, 'error': None}

class Form(StatesGroup):
    waiting_for_path = State()
    editing_path = State()

async def init_db():
    async with aiosqlite.connect(DB) as db:
        await db.execute("""
            CREATE TABLE IF NOT EXISTS paths (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                path TEXT NOT NULL,
                type TEXT NOT NULL CHECK(type IN ('folder', 'file')),
                interval TEXT DEFAULT '24h',
                last_backup TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        await db.commit()

def get_main_kb():
    kb = InlineKeyboardMarkup(row_width=2)
    kb.add(
        InlineKeyboardButton("📁 Указать папку", callback_data="add_folder"),
        InlineKeyboardButton("📄 Указать файл", callback_data="add_file")
    )
    kb.add(InlineKeyboardButton("📋 Мои пути", callback_data="list_paths"))
    kb.add(InlineKeyboardButton("📊 Статус", callback_data="status"))
    return kb

def get_interval_kb(path_type, path):
    kb = InlineKeyboardMarkup(row_width=2)
    for label, value in [("🔁 1ч", "1h"), ("🕕 6ч", "6h"), ("🕛 12ч", "12h"), ("☀️ 24ч", "24h")]:
        kb.insert(InlineKeyboardButton(label, callback_data=f"set_interval|{path_type}|{path}|{value}"))
    kb.add(InlineKeyboardButton("🔙 Назад", callback_data="list_paths"))
    return kb

def get_confirmation_kb(typ, path):
    kb = InlineKeyboardMarkup()
    kb.add(
        InlineKeyboardButton("✅ Да", callback_data=f"confirm_backup|{typ}|{path}"),
        InlineKeyboardButton("❌ Нет", callback_data="main_menu")
    )
    return kb

def get_manage_kb(typ, path):
    kb = InlineKeyboardMarkup()
    kb.add(InlineKeyboardButton("🗑 Удалить", callback_data=f"delete|{typ}|{path}"))
    kb.add(InlineKeyboardButton("✏️ Изменить интервал", callback_data=f"edit_interval|{typ}|{path}"))
    kb.add(InlineKeyboardButton("🔙 Назад", callback_data="list_paths"))
    return kb

@dp.message(commands=['start'])
async def cmd_start(message):
    if message.from_user.id not in ADMIN:
        return await message.answer("⛔️ У вас нет доступа.")
    await message.answer("🔧 Главное меню:", reply_markup=get_main_kb())

@dp.callback_query(lambda c: c.data == "status")
async def status(callback_query):
    if backup_task_status['running']:
        msg = "✅ Служба работает. Ожидаем времени бэкапа."
    else:
        msg = f"❌ Ошибка: {backup_task_status['error']}"
    await bot.send_message(callback_query.from_user.id, msg)

@dp.callback_query(lambda c: c.data == "add_folder" or c.data == "add_file")
async def add_path_prompt(callback_query, state: FSMContext):
    await Form.waiting_for_path.set()
    await state.update_data(type='folder' if callback_query.data == 'add_folder' else 'file')
    await callback_query.message.edit_text("📥 Введите абсолютный путь:", reply_markup=InlineKeyboardMarkup().add(
        InlineKeyboardButton("❌ Отмена", callback_data="cancel")
    ))

@dp.callback_query(lambda c: c.data == "cancel", state='*')
async def cancel_action(callback_query, state: FSMContext):
    await state.finish()
    await callback_query.message.edit_text("❌ Отменено.", reply_markup=get_main_kb())

@dp.callback_query(lambda c: c.data == "list_paths")
async def show_paths(callback_query):
    async with aiosqlite.connect(DB) as db:
        async with db.execute("SELECT path, type, interval FROM paths") as cursor:
            rows = await cursor.fetchall()
    if not rows:
        return await callback_query.message.edit_text("🗂 Список пуст.", reply_markup=get_main_kb())
    kb = InlineKeyboardMarkup()
    for path, typ, interval in rows:
        label = f"{'📁' if typ == 'folder' else '📄'} {path} ({interval})"
        kb.add(InlineKeyboardButton(label, callback_data=f"manage|{typ}|{path}"))
    kb.add(InlineKeyboardButton("🔙 Назад", callback_data="main_menu"))
    await callback_query.message.edit_text("🗂 Список путей:", reply_markup=kb)

@dp.message(state=Form.waiting_for_path)
async def process_path(message, state: FSMContext):
    user_data = await state.get_data()
    path = message.text.strip()
    if not os.path.exists(path):
        await message.reply("❌ Путь не существует.")
        return await state.finish()
    async with aiosqlite.connect(DB) as db:
        await db.execute("INSERT INTO paths (path, type) VALUES (?, ?)", (path, user_data['type']))
        await db.commit()
    await state.finish()
    await message.answer("✅ Добавлено. Выберите частоту:", reply_markup=get_interval_kb(user_data['type'], path))

@dp.callback_query(lambda c: c.data.startswith("set_interval|"))
async def set_interval(callback_query):
    _, typ, path, interval = callback_query.data.split('|', 3)
    async with aiosqlite.connect(DB) as db:
        await db.execute("UPDATE paths SET interval = ? WHERE path = ? AND type = ?", (interval, path, typ))
        await db.commit()
    await callback_query.message.edit_text("🔄 Сделать бэкап прямо сейчас?", reply_markup=get_confirmation_kb(typ, path))

@dp.callback_query(lambda c: c.data.startswith("confirm_backup|"))
async def confirm_backup(callback_query):
    _, typ, path = callback_query.data.split('|', 2)
    try:
        if typ == 'folder':
            zip_path = f"/tmp/backup_{os.path.basename(path)}.zip"
            with zipfile.ZipFile(zip_path, 'w') as zipf:
                for root, _, files in os.walk(path):
                    for file in files:
                        fp = os.path.join(root, file)
                        zipf.write(fp, os.path.relpath(fp, path))
            await bot.send_document(callback_query.from_user.id, open(zip_path, 'rb'), caption=f"📦 Ручной бэкап:{path}")
            os.remove(zip_path)
        elif typ == 'file':
            await bot.send_document(callback_query.from_user.id, open(path, 'rb'), caption=f"📄 Ручной бэкап:{path}")
    except Exception as e:
        await callback_query.message.edit_text(f"⚠️ Ошибка при ручном бэкапе:{path}\n{e}", reply_markup=get_main_kb())
        return
    await callback_query.message.edit_text("✅ Бэкап выполнен. Работа продолжается в фоне.", reply_markup=get_main_kb())

@dp.callback_query(lambda c: c.data == "main_menu")
async def go_main(callback_query):
    await callback_query.message.edit_text("🔧 Главное меню:", reply_markup=get_main_kb())

@dp.callback_query(lambda c: c.data.startswith("manage|"))
async def manage_path(callback_query):
    _, typ, path = callback_query.data.split('|', 2)
    await callback_query.message.edit_text(f"🔧 Управление путем:{path}", reply_markup=get_manage_kb(typ, path))

@dp.callback_query(lambda c: c.data.startswith("delete|"))
async def delete_path(callback_query):
    _, typ, path = callback_query.data.split('|', 2)
    async with aiosqlite.connect(DB) as db:
        await db.execute("DELETE FROM paths WHERE path = ? AND type = ?", (path, typ))
        await db.commit()
    await callback_query.message.edit_text("✅ Путь удалён.", reply_markup=get_main_kb())

@dp.callback_query(lambda c: c.data.startswith("edit_interval|"))
async def edit_interval(callback_query):
    _, typ, path = callback_query.data.split('|', 2)
    await callback_query.message.edit_text("⏱ Выберите новый интервал:", reply_markup=get_interval_kb(typ, path))

async def backup_scheduler():
    while True:
        try:
            now = datetime.utcnow()
            async with aiosqlite.connect(DB) as db:
                async with db.execute("SELECT id, path, type, interval, last_backup FROM paths") as cursor:
                    paths = await cursor.fetchall()
                for row in paths:
                    id_, path, typ, interval, last_backup = row
                    delta = {
                        "1h": timedelta(hours=1),
                        "6h": timedelta(hours=6),
                        "12h": timedelta(hours=12),
                        "24h": timedelta(hours=24)
                    }.get(interval, timedelta(hours=24))
                    last_time = datetime.strptime(last_backup, "%Y-%m-%d %H:%M:%S")
                    if now - last_time >= delta:
                        try:
                            if typ == 'folder':
                                zip_path = f"/tmp/backup_{os.path.basename(path)}.zip"
                                with zipfile.ZipFile(zip_path, 'w') as zipf:
                                    for root, _, files in os.walk(path):
                                        for file in files:
                                            fp = os.path.join(root, file)
                                            zipf.write(fp, os.path.relpath(fp, path))
                                await bot.send_document(ADMIN[0], open(zip_path, 'rb'), caption=f"📦 Автобэкап:{path}")
                                os.remove(zip_path)
                            elif typ == 'file':
                                await bot.send_document(ADMIN[0], open(path, 'rb'), caption=f"📄 Автобэкап:{path}")
                            await db.execute("UPDATE paths SET last_backup = ? WHERE id = ?", (now.strftime("%Y-%m-%d %H:%M:%S"), id_))
                            await db.commit()
                        except Exception as e:
                            await bot.send_message(ADMIN[0], f"⚠️ Ошибка при бэкапе:{path}{e}")
            backup_task_status['running'] = True
            backup_task_status['error'] = None
        except Exception as e:
            backup_task_status['running'] = False
            backup_task_status['error'] = str(e)
        await asyncio.sleep(60)

if __name__ == '__main__':
    logging.basicConfig(level=logging.INFO)
    loop = asyncio.get_event_loop()
    loop.run_until_complete(init_db())
    loop.create_task(backup_scheduler())
    dp.start_polling()