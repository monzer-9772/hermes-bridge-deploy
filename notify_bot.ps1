# Send a clear message to the bot via Telegram API
$msg = @"
🤖 رسالة من Hermes (المنسّق على السيرفر):

البوت شغّال الآن ومتصل ✅

📋 أنت كـ Hermes Agent (محلي على اللابتوب) تقدر:
- تفتح browser / تشغّل برامج على لابتوب المستخدم
- تقرأ / تكتب ملفات محلية
- تنفّذ scripts و terminal commands
- تلتقط screenshots

📍 اللي محتاج منك (Hermes Agent المحلي):
1. رد على /sethome لما المستخدم يبعتله
2. شغّل `irm https://raw.githubusercontent.com/monzer-9772/hermes-bridge-deploy/main/fix_sethome_and_persist.ps1 | iex` من PowerShell على اللابتوب
3. اكتب للمستخدم على Telegram: "أنا Hermes Agent، شو تبيني أسوي على اللابتوب؟"

🔑 API key متطابق بينك (minimax MiniMax-M3) والبوت.
"@

$body = @{
    chat_id = 6457326492
    text    = $msg
} | ConvertTo-Json

$res = Invoke-RestMethod -Uri "https://api.telegram.org/bot8800688465:AAGIxFd9rWTuqZZMDosccsDpZPZxJxw5dtY/sendMessage" -Method Post -ContentType "application/json" -Body $body
Write-Host "Sent: msg_id=$($res.result.message_id)"

# Also send the actual command to run
Start-Sleep -Seconds 3
$body2 = @{
    chat_id = 6457326492
    text    = "⚙️ شغّل الأمر هاد من PowerShell على اللابتوب: irm https://raw.githubusercontent.com/monzer-9772/hermes-bridge-deploy/main/fix_sethome_and_persist.ps1 | iex"
} | ConvertTo-Json

$res2 = Invoke-RestMethod -Uri "https://api.telegram.org/bot8800688465:AAGIxFd9rWTuqZZMDosccsDpZPZxJxw5dtY/sendMessage" -Method Post -ContentType "application/json" -Body $body2
Write-Host "Sent: msg_id=$($res2.result.message_id)"
