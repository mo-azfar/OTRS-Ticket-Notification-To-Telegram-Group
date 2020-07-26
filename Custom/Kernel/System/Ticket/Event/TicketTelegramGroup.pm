# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --
#Send ticket notification to Telegram group based on Queue upon ticket action. E.g: TicketQueueUpdate
package Kernel::System::Ticket::Event::TicketTelegramGroup;

use strict;
use warnings;

# use ../ as lib location
use File::Basename;
use FindBin qw($RealBin);
use lib dirname($RealBin);

use JSON::MaybeXS; #yum install -y perl-JSON-MaybeXS
use LWP::UserAgent;  #yum install -y perl-LWP-Protocol-https
use HTTP::Request::Common;

our @ObjectDependencies = (
    'Kernel::System::Ticket',
    'Kernel::System::Log',
	'Kernel::System::Group',
	'Kernel::System::Queue',
	'Kernel::System::User',
	
);

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;
    
	#my $parameter = Dumper(\%Param);
    #$Kernel::OM->Get('Kernel::System::Log')->Log(
    #    Priority => 'error',
    #    Message  => $parameter,
    #);
	
	# check needed param
    if ( !$Param{TicketID} || !$Param{New}->{Text1} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need TicketID || Text1 (Param and Value) for this operation',
        );
        return;
    }

    #my $TicketID = $Param{Data}->{TicketID};  ##This one if using sysconfig ticket event
	my $TicketID = $Param{TicketID};  ##This one if using GenericAgent ticket event
	my $Text1 = $Param{New}->{'Text1'}; ##This one if using GenericAgent ticket event
    
	if ( defined $Param{New}->{'Text2'} ) { $Text1 = "$Text1<br/>$Param{New}->{Text2}"; }
	
	my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
	
	# get ticket content
	my %Ticket = $TicketObject->TicketGet(
        TicketID => $TicketID ,
		UserID        => 1,
		DynamicFields => 1,
		Extended => 0,
    );
	
	return if !%Ticket;
	
	#print "Content-type: text/plain\n\n";
	#print Dumper(\%Ticket);
	
	my $LogObject     = $Kernel::OM->Get('Kernel::System::Log');
	my $UserObject = $Kernel::OM->Get('Kernel::System::User');
	my $CustomerUserObject = $Kernel::OM->Get('Kernel::System::CustomerUser');
	my $QueueObject = $Kernel::OM->Get('Kernel::System::Queue');
	my $QueueID = $QueueObject->QueueLookup( Queue => $Ticket{Queue} );
	my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
	
	
	# prepare owner fullname based on Text1 tag
    if ( $Text1 =~ /<OTRS_OWNER_UserFullname>/ ) {
		my %OwnerPreferences = $UserObject->GetUserData(
        UserID        => $Ticket{OwnerID},
        NoOutOfOffice => 0,
    );
	
	for ( sort keys %OwnerPreferences ) {
        $Text1 =~ s/<OTRS_OWNER_UserFullname>/$OwnerPreferences{UserFullname}/g;
		}   
    }
	
	# prepare responsible fullname based on Text1 tag
    if ( $Text1 =~ /<OTRS_RESPONSIBLE_UserFullname>/ ) {
		my %ResponsiblePreferences = $UserObject->GetUserData(
        UserID        => $Ticket{ResponsibleID},
        NoOutOfOffice => 0,
    );
	
	for ( sort keys %ResponsiblePreferences ) {
        $Text1 =~ s/<OTRS_RESPONSIBLE_UserFullname>/$ResponsiblePreferences{UserFullname}/g;
		}   
    }
	
	# prepare customer fullname based on text1 tag
    if ( $Text1 =~ /<OTRS_CUSTOMER_UserFullname>/ ) {
		my $FullName = $CustomerUserObject->CustomerName( UserLogin => $Ticket{CustomerUserID} );
		$Text1 =~ s/<OTRS_CUSTOMER_UserFullname>/$FullName/g;
    };
	
	#change to < and > for text1 tag
	$Text1 =~ s/&lt;/</ig;
	$Text1 =~ s/&gt;/>/ig;	
	
	#get data based on text1 tag
	my $RecipientText1 = $Kernel::OM->Get('Kernel::System::Ticket::Event::NotificationEvent::Transport::Email')->_ReplaceTicketAttributes(
        Ticket => \%Ticket,
        Field  => $Text1,
    );
	
	my $HTMLUtilsObject = $Kernel::OM->Get('Kernel::System::HTMLUtils');
	#strip all html tag 
    my $Message1 = $HTMLUtilsObject->ToAscii( String => $RecipientText1 );	
	
	my $HttpType = $ConfigObject->Get('HttpType');
	my $FQDN = $ConfigObject->Get('FQDN');
	my $ScriptAlias = $ConfigObject->Get('ScriptAlias');
	
	my $DateTimeObject = $Kernel::OM->Create('Kernel::System::DateTime', ObjectParams => { String   => $Ticket{Created},});
	my $DateTimeString = $DateTimeObject->Format( Format => '%Y-%m-%d %H:%M' );
	
	my $Token = $ConfigObject->Get('TicketTelegramGroup::Token');	
	my $TelegramGroupChatID;
    my %TelegramGroupChatIDs = %{ $ConfigObject->Get('TicketTelegramGroup::ChatID') };
	
	for my $ChatIDQueue ( sort keys %TelegramGroupChatIDs )   
	{
		next if $Ticket{Queue} ne $ChatIDQueue;
		$TelegramGroupChatID = $TelegramGroupChatIDs{$ChatIDQueue};
        # error if queue is defined but Webhook URLis empty
        if ( !$TelegramGroupChatID )
        {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'notice',
                Message  => "No Telegram Chat ID defined for Queue $Ticket{Queue}"
            );
            return;
        }
  	    
		my $TicketURL = $HttpType.'://'.$FQDN.'/'.$ScriptAlias.'index.pl?Action=AgentTicketPrint;TicketID='.$TicketID;	
					
		# For Asynchronous sending
		my $TaskName = substr "Recipient".rand().$TelegramGroupChatID, 0, 255;
		
		# instead of direct sending, we use task scheduler
		my $TaskID = $Kernel::OM->Get('Kernel::System::Scheduler')->TaskAdd(
			Type                     => 'AsynchronousExecutor',
			Name                     => $TaskName,
			Attempts                 =>  1,
			MaximumParallelInstances =>  0,
			Data                     => 
			{
				Object   => 'Kernel::System::Ticket::Event::TicketTelegramGroup',
				Function => 'SendMessageTelegramGroup',
				Params   => 
						{
							TicketURL => $TicketURL,
							Token    => $Token,
							TelegramGroupChatID  => $TelegramGroupChatID,
							Message      => $Message1,
							TicketID      => $TicketID, #sent for log purpose
							Queue      => $Ticket{Queue}, #sent for log purpose
						},
			},
		);
					
	}

}

=cut

		my $Test = $Self->SendMessageTelegramGroup(
			TicketURL => $TicketURL,
			Token    => $Token,
			TelegramGroupChatID  => $TelegramGroupChatID,
			Message      => $Message1,
			TicketID      => $TicketID, #sent for log purpose
			Queue      => $Ticket{Queue}, #sent for log purpose
		);

=cut

sub SendMessageTelegramGroup {
	my ( $Self, %Param ) = @_;

	# check for needed stuff
    for my $Needed (qw(TicketURL Token TelegramGroupChatID Message TicketID Queue)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Missing parameter $Needed!",
            );
            return;
        }
    }

	my $ua = LWP::UserAgent->new;
	utf8::decode($Param{Message});
	my $p = {
			chat_id=>$Param{TelegramGroupChatID},
			parse_mode=>'HTML',
			text=>$Param{Message},
			reply_markup => {
				#resize_keyboard => \1, # \1 = true when JSONified, \0 = false
				inline_keyboard => [
				# Keyboard: row 1
				[
				
				{
                text => 'View',
                url => $Param{TicketURL}
				}
                  
				]
				]
				}
			};
	
	my $response = $ua->request(
		POST "https://api.telegram.org/bot".$Param{Token}."/sendMessage",
		Content_Type    => 'application/json',
		Content         => JSON::MaybeXS::encode_json($p)
       )	;
	
	my $ResponseData = $Kernel::OM->Get('Kernel::System::JSON')->Decode(
        Data => $response->decoded_content,
    );
	
	if ($ResponseData->{ok} eq 0)
	{
	$Kernel::OM->Get('Kernel::System::Log')->Log(
			 Priority => 'error',
			 Message  => "Telegram group notification to Queue $Param{Queue} ($Param{TelegramGroupChatID}): $ResponseData->{description}",
		);
	}
	else
	{
	my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
	my $TicketHistory = $TicketObject->HistoryAdd(
        TicketID     => $Param{TicketID},
        HistoryType  => 'SendAgentNotification',
        Name         => "Sent Telegram Group Notification for Queue $Param{Queue}",
        CreateUserID => 1,
		);			
	}
}

1;

