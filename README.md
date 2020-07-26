# OTRS-Ticket-Notification-To-Telegram-Group
- Built for OTRS CE v 6.0.x  
- Send ticket notification to SPECIFIC TELEGRAM GROUP based on Queue upon ticket action. E.g: TicketQueueUpdate  

1. A telegram bot must be created by chat with @FatherBot and obtain the token via Telegram.  
  
2. Update the telegram bot token at System Configuration > TicketTelegramGroup::Token  

3. Update the telegram group chat_id in System Configuration > TicketTelegramGroup::ChatID  

		Queue 1 Name => Group 1 Telegram Chat ID  
		
		Example:
		Misc => 1001186418888  
		an so on..
    
		Notes:
		* Add the bot (1) into the your telegram group and start the conversation with the bot first. 
		
		e.g: /hello @BOT_NAME    
		
		* By using  https://api.telegram.org/bot<TOKEN>/getUpdates , we can obtain the chat_id of the group    


4. Admin must create a new Generic Agent (GA) with option to execute custom module.  

		[Mandatory][Name]: Up to you.
		[Mandatory][Event Based Execution] : Mandatory. Up to you. Example, TicketQueueUpdate for moving ticket to another queue
		[Optional][Select Ticket]: Optional. Up to you.
		[Mandatory][Execute Custom Module] : Module => Kernel::System::Ticket::Event::TicketTelegramGroup
	
		[Mandatory][Param 1 Key] : Text1  
		[Mandatory][Param 1 Value] : Text to be sent to the user.
		[Optional][Param 2 Key] : Text2  
		[Optional][Param 2 Value] : Additional text to be sent to the user.
		
		#Support OTRS ticket TAG only. bold, newline must be in HTML code.  
		#Support <OTRS_NOTIFICATION_RECIPIENT_UserFullname>, <OTRS_OWNER_UserFullname>, <OTRS_RESPONSIBLE_UserFullname> and <OTRS_CUSTOMER_UserFullname> tag.
	

[![download.png](https://i.postimg.cc/YqVxSc86/download.png)](https://postimg.cc/qzsKm5Pq)


5. To test the connection to telegram,

	shell > curl -X GET https://api.telegram.org/bot<TELEGRAM_BOT_TOKEN>/getMe