# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --
#Send a GROUP telegram notification to SPECIFIC GROUP based on Queue upon ticket action. E.g: TicketQueueUpdate
#
#
#20200329 - 1st release based on TicketTelegramAgent.pm.
#20200330 - Adding support to sent Text2 Param (Optional field). 
#20200412 - Using otrs web user agent method to send telegram
package Kernel::System::Ticket::Event::TicketTelegramGroup;

use strict;
use warnings;

# use ../ as lib location
use File::Basename;
use FindBin qw($RealBin);
use lib dirname($RealBin);

use Data::Dumper;
use Fcntl qw(:flock SEEK_END);
use JSON::MaybeXS;
#yum install -y perl-LWP-Protocol-https
#yum install -y perl-JSON-MaybeXS

our @ObjectDependencies = (
    'Kernel::System::Ticket',
    'Kernel::System::Log',
	'Kernel::System::Group',
	'Kernel::System::Queue',
	'Kernel::System::User',
	
);

=head1 NAME

Kernel::System::ITSMConfigItem::Event::DoHistory - Event handler that does the history

=head1 SYNOPSIS

All event handler functions for history.

=head1 PUBLIC INTERFACE

=over 4

=cut

=item new()

create an object

    use Kernel::System::ObjectManager;
    local $Kernel::OM = Kernel::System::ObjectManager->new();
    my $DoHistoryObject = $Kernel::OM->Get('Kernel::System::ITSMConfigItem::Event::DoHistory');

=cut

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
	my $WebUserAgentObject = $Kernel::OM->Get('Kernel::System::WebUserAgent');
	
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
  	    
		###START SENDING TELEGRAM
		my $url = $HttpType.'://'.$FQDN.'/'.$ScriptAlias.'index.pl?Action=AgentTicketPrint;TicketID='.$TicketID;
		#create a hash of your reply markup
		my %replyMarkup  = (
				inline_keyboard    => [[ 
				{
					text => 'View',
					##callback_data => "Print"
					url => $url
				}
		
				]]
				);#keyboard must be an array of array
		
		#Json encode
		my $buttons = encode_json \%replyMarkup;
		
		my %Response = $WebUserAgentObject->Request(
			URL          => "https://api.telegram.org/bot$Token/sendMessage",
			Type         => 'POST',
			Data         => {
							chat_id=>$TelegramGroupChatID,
							parse_mode=>'HTML',
							text=>$Message1,
							reply_markup => $buttons,
							},
			Header => {
				Content_Type  => 'application/json',
			},
			SkipSSLVerification => 0, # (optional)
			NoLog               => 0, # (optional)
		);
		
		
		#my $content  = $Response->decoded_content();
		my @resCode = split / /, $Response{Status};
	
		##RESPONSE CODE 200 - Sent
		##RESPONSE CODE 400 - ChAT NOT FOUND
		##RESPONSE CODE 401 - UNAITHORIZED
		my $result;
		if ($resCode[0] eq "200")
		{
		$result="Success";
		}
		else
		{
		$result = $resCode[0];
		}
		
		my $TicketHistory = $TicketObject->HistoryAdd(
        TicketID     => $TicketID,
        QueueID      => $QueueID,
        HistoryType  => 'SendAgentNotification',
        Name         => "Telegram Notification to $Ticket{Queue} : $result",
        CreateUserID => 1,
		);			
		
	}

}

1;

