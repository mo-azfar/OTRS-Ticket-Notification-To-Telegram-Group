# OTRS-Ticket-Notification-To-Telegram-Group
- Built for OTRS CE v 6.0.x
- Send a telegram notification to SPECIFIC TELEGRAM GROUP based on Queue upon ticket action. E.g: TicketQueueUpdate

1. A telegram bot must be created by chat with @FatherBot and obtain the token via Telegram.

2. Update the telegram bot token at System Configuration > TicketTelegramGroup::Token

3. Update the telegram group chat_id in System Configuration > TicketTelegramGroup::ChatID

Queue 1 Name => Group 1 Telegram Chat ID  
Misc => 1001186418888  
an so on..

* Add the bot (1) into the your telegram group and start the conversation with the created telegram bot first by using telegram. e.g: /hello @BOT_NAME  
* By using  https://api.telegram.org/bot<TOKEN>/getUpdates , we can obtain the chat_id of the group

4. Admin must create a new Generic Agent (GA) with option to execute custom module.

Execute Custom Module => Module => Kernel::System::Ticket::Event::TicketTelegramGroup
	
[MANDATORY PARAM]
	
Param 1 Key => Text1  
Param 1 Value => *Text to be sent to the user.  
#Also support OTRS ticket TAG only. bold, newline must be in HTML code.  
#Also support <OTRS_NOTIFICATION_RECIPIENT_UserFullname>, <OTRS_OWNER_UserFullname>, <OTRS_RESPONSIBLE_UserFullname> and <OTRS_CUSTOMER_UserFullname> tag.
	
[OPTINAL PARAM]
	
Param 2 Key => Text2  
Param 2 Value => *Additional text to be sent to the user.  
#Also support OTRS ticket TAG only. bold, newline must be in HTML code.  
#Also support <OTRS_NOTIFICATION_RECIPIENT_UserFullname>, <OTRS_OWNER_UserFullname>, <OTRS_RESPONSIBLE_UserFullname> and <OTRS_CUSTOMER_UserFullname> tag.


[![download.png](https://i.postimg.cc/YqVxSc86/download.png)](https://postimg.cc/qzsKm5Pq)
