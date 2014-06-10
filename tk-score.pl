#!/usr/bin/perl -w
#
# tk-score - Managing and reporting the results and standings of a
# soccer league that plays once a week on tuesdays.  This is reflected
# in the lack of scheduling options as currently avaible.

use strict;

# Where you can find extra modules?
use lib "$ENV{HOME}/lib/perl";
# Remove cwd
no lib ".";

use IO::Handle;
#use Data::Dumper;
#use Date::Calc qw(Decode_Date_US Delta_Days Add_Delta_Days);
use Getopt::Long;
use List::Util 'shuffle';
use Pod::Usage;
use YAML qw(DumpFile LoadFile);

# Non-core Perl modules we require
my $count = 0;
foreach my $mod ("Tk", "Tk::BrowseEntry","Tk::DateEntry","Tk::HList","Tk::ItemStyle","Tk::DialogBox","Tk::Month", "Tk::FileSelect", "Date::Calc qw(Decode_Date_US Delta_Days Add_Delta_Days)") {
  eval "use $mod;1";
  if ($@) {
    warn "  Missing: $mod\n";
    $count++;
  }
}
die "\nPlease install the above modules (from CPAN) to run this program.\n\n" if $count;

# Nice to have modules for making pretty reports.
my $have_pdf = 1;
$count = 0;
foreach my $mod (qw(PDF::API2 PDF::Table)) {
  eval "use $mod; 1";
  if ($@) {
    warn "  Missing: $mod\n";
    $count++;
    $have_pdf = 0;
  }
}
warn "\nPlease install the above modules to generate PDF reports.\n" if $count;


#---------------------------------------------------------------------
# Defaults and global variables.  
#---------------------------------------------------------------------

my $VERSION = "v1.7 (2013-05-22)";
my $gf_version = "v2.0";

my $game_file = "";
my $rpt_file = "new-season.rpt";
my $do_report = 0;

my $NeedSave = 0;

# Flush all output right away...
$|=1;

#---------------------------------------------------------------------
my @matches = ();
my @scores = ( '','F',0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15);
my %lining_team;
my %bye_team;
my $homeforfeit= 0;
my $homecoed = 'no';
my $homescore = " ";
my $match_datelist;

# Style Colors for DateList, made global so we can update them
# easily.  Might not need to do this down the line though....
my $dls_red;
my $dls_green;
my $dls_done;
my $dls_blue;

my $notokcolor = 'darkgrey';
my $okcolor    = 'lightgreen';

# Format is # -> Name
my @teams;

# Debugging and option parsing
my $DEBUG;
my $prog_help;
my $man;
my $initialize_season = 0;

#---------------------------------------------------------------------
# These schedules should be stored in a YAML file somewhere else.
#---------------------------------------------------------------------

my $dolining = 1;   # Do teams need to line during the season?

# Week 0 is practice if used.  But numbering starts from 1!!!  Data
# Structure, which should be in an YAML file instead, though this way
# it works for DSL stuff nicely.  Other leagues might have other
# needs.  
my $first_match_scrimmage = 0;

# %sched_template = ( Number_Teams => {
#                     Week => [game,game,game,game,bye,lining],
#                     ....
#                    }
#                  );    

my %sched_template = 
  ( 8 => {
	  0  => [ "1-7", "2-3", "5-8", "4-6", "", "1" ],
	  1  => [ "1-2", "3-4", "5-6", "7-8", "", "1" ],
	  2  => [ "5-7", "6-8", "1-3", "2-4", "", "5" ],
	  3  => [ "4-8", "1-5", "2-6", "3-7", "", "5" ],
	  4  => [ "2-5", "3-8", "4-7", "1-6", "", "3" ],
	  5  => [ "3-6", "2-7", "1-8", "4-5", "", "3" ],
	  6  => [ "1-7", "4-6", "2-8", "3-5", "", "4" ],
	  7  => [ "4-1", "7-6", "8-5", "3-2", "", "4" ],
	  8  => [ "8-7", "6-5", "4-3", "2-1", "", "6" ],
	  9  => [ "4-2", "3-1", "8-6", "7-5", "", "2" ],
	  10 => [ "7-3", "6-2", "5-1", "8-4", "", "7" ],
	  11 => [ "6-1", "7-4", "8-3", "5-2", "", "7" ],
	  12 => [ "5-4", "8-1", "7-2", "6-3", "", "8" ],
	  13 => [ "5-3", "8-2", "6-4", "7-1", "", "8" ],
	  14 => [ "2-3", "5-8", "6-7", "1-4", "", "2" ],
	  15 => [ "Make-up", "Make-up", "Make-up", "Make-up", "", "tbd" ],
	  16 => [ "Playoffs", "Playoffs", "Playoffs", "Playoffs", "", "tbd" ],
	  17 => [ "Playoffs", "Playoffs", "Playoffs", "Playoffs", "", "tbd" ],
	  18 => [ "Playoffs", "Playoffs", "Playoffs", "Playoffs", "", "tbd" ],
	 },
    9 => {
	  1  => [ "3-7", "5-9", "4-6", "2-8", "1", "9" ],
	  2  => [ "1-2", "4-9", "5-7", "6-8", "3", "9" ],
	  3  => [ "4-8", "1-3", "7-9", "5-6", "2", "8" ],
	  4  => [ "3-8", "6-7", "1-4", "2-9", "5", "8" ],
	  5  => [ "6-9", "7-8", "2-3", "1-5", "4", "6" ],
	  6  => [ "1-6", "2-4", "3-9", "5-8", "7", "6" ],
	  7  => [ "2-5", "1-7", "8-9", "3-4", "6", "5" ],
	  8  => [ "4-7", "3-5", "1-8", "2-6", "9", "5" ],
	  9  => [ "4-5", "3-6", "2-7", "1-9", "8", "4" ],
	  10 => [ "2-8", "4-6", "5-9", "3-7", "1", "4" ],
	  11 => [ "6-8", "5-7", "4-9", "1-2", "3", "7" ],
	  12 => [ "5-6", "7-9", "1-3", "4-8", "2", "7" ],
	  13 => [ "2-9", "1-4", "6-7", "3-8", "5", "1" ],
	  14 => [ "1-5", "2-3", "7-8", "6-9", "4", "1" ],
	  15 => [ "5-8", "3-9", "2-4", "1-6", "7", "3" ],
	  16 => [ "3-4", "8-9", "1-7", "2-5", "6", "3" ],
	  17 => [ "2-6", "1-8", "3-5", "4-7", "9", "2" ],
	  18 => [ "1-9", "2-7", "3-6", "4-5", "8", "2" ],
	  19 => [ "Playoffs", "Playoffs", "Playoffs", "Playoffs" ],
	  20 => [ "Playoffs", "Playoffs", "Playoffs", "Playoffs" ]
	 },
  );

my $match_template = { Week => 0,
                       Date => '',
                       Time => '',
                       Field => '',
                       Home => 0,
                       Away => 0,
                       HomeScore => "",
                       HomeCoed => 0,
                       HomePoints => 0,
                       AwayScore => "",
                       AwayCoed => 0,
                       AwayPoints => 0,
                       Complete => 0,
                    };

my $playoff_sched = 
  { "Three Weeks, 8 Teams" => 
    { 1 => [ "1-8 (A)", "2-7 (B)", "3-6 (C)", "4-5 (D)" ], 
      2 => [ "W:A-W:D (E)", "W:B-W:C (F)", "L:D-L:A (G)", "L:C-L:B (H)" ],
      3 => [ "W:E-W:F (Final)", "L:E-L:F", "W:G-W:H", "L:G-L:H" ],
    },
    "Two Weeks, 8 Teams" => 
    { 1 => [ "1-4 (A)", "2-3 (B)", "5-8 (C)", "6-7 (D)" ], 
      2 => [ "W:A-W:B (Final)", "L:A-L:B", "W:C-W:D", "L:C-L:D" ],
    },
		    };

# Number of teams supported by schedules.
my @teamcnt = sort(qw(8 9));
my $max_numteams = $teamcnt[$#teamcnt];
my $numteams = $teamcnt[0];

my @playoff_rnds = qw(3 2);
my @game_times = ("6pm & 7pm", "7pm & 8pm");
my $playoff_rnd = $playoff_rnds[0];

# Two rounds of games for each team playing every other team.
my $numweeks = ($numteams - 1) * 2;
my $week = 1;
my $curweek = 0;
my $weekdate= "";
my @weeks;
my $matches_per_week = 4;

# Per-team standings.  Re-calculated depending on the week showing.
my $cnt = 1;
my %curmatch = &init_matches_per_week($matches_per_week);
my %standings;
my %season;

#---------------------------------------------------------------------
# Sort the %standings array (see zero_standings for format) by RANK,
# W, L, T and maybe more...

#---------------------------------------------------------------------
sub cleanup_and_exit {
  my $top = shift;
  my $game_file = shift;

  if ($NeedSave) {
    print "We gotta save first dude!\n\n";
    
    my $text = "You have unsaved changes, do you want to Save and Exit, Exit without Save, or return to editing the	Season?";
    
    my $dialog = $top->DialogBox(-title => "Unsaved changes!",
				 -buttons => [ 'Save and Exit', 
					       'Exit without Save',
					       'Cancel', ],
				 -default_button => 'Cancel');
    $dialog->add('Label', -text => $text, -width => '30');
    
    my $ok = 1;
    while ($ok) {
      my $answer = $dialog->Show( );
      
      return if ($answer eq "Cancel");
      &do_exit($dialog,$top) if ($answer eq "Exit without Save");
      
      if ($answer eq "Save and Exit") {
	&save_game_file_as($top, $game_file,
			   \@teams,\@matches,\%standings,\%season);
	&do_exit($dialog,$top);
      }
    }
  }
  else {
    &do_exit($top);
  }
}


#---------------------------------------------------------------------
sub do_exit {

  foreach my $top (@_) {
    $top->destroy;
  }
  &Tk::exit;
}

#---------------------------------------------------------------------
sub init_matches_per_week {

  # Matches per-week that are played.
  my $num = shift @_;

  my %t;

  for (my $m=1; $m <= $num; $m++) {
	$t{$m}->{HomeScore} = "";
	$t{$m}->{HomeCoed} = 0;
	$t{$m}->{HomePoints} = "";
	$t{$m}->{AwayScore} = "";
	$t{$m}->{AwayCoed} = 0;
	$t{$m}->{AwayPoints} = "";
	$t{$m}->{PointsLabels} = ();
  }
  return %t;
}
#---------------------------------------------------------------------
sub byweektimefield {
  $a->{Week} <=> $b->{Week} ||
    $a->{Time} cmp $b->{Time} ||
        $a->{Field} cmp $b->{Field};
}

#---------------------------------------------------------------------
# If $new is blank, update all dates...  I think.
sub updateweekdates {
  my $old = shift;
  my $new = shift;
  
  print "updateweekdates(\"$old\",\"$new\")\n";
  
  my %dates;
  my $found=0;
  foreach my $match (sort byweektimefield @matches) {
    if ($old eq "" && $new eq "") {
      $match->{"Date"} = "$old";
    }
    elsif ($match->{"Date"} eq $old) {
      $match->{"Date"} = "$new ($old)";
      $match->{"DateOrig"} = "$old";
      print "  match->{Date} = ", $match->{Date}, "\n";
      $found++;
    }
  }
  return $found;
}

#---------------------------------------------------------------------
# Input:  Week Number
# Return: Date of the matches that week.
# Notes:  All matches are on the same day.

sub week2date {
  my $w = shift;

  foreach my $match (sort byweektimefield @matches) {
    if ($match->{"Week"} == $w) {
      my $d = $match->{Date};
      #print "Week = $w, Date = $d\n";
      return $d;
    }
  }
}

#---------------------------------------------------------------------
sub penalty_init {
  my $top = shift;

  my $win = MainWindow->new();
  $win->title("Penalties");
  $win->configure(-height => 400,
                  -width => 800,
                  -background => 'white',
	);
  $win->geometry('-500-500');
  $win->optionAdd('*font', 'Helvetica 9');
  

  my $hl = $win->Scrolled('HList', -scrollbars => 'ow',
                          -columns=>3, -header => 1, 
						  -selectmode => 'single', -width => 40,
	)->pack(-fill => 'x'); 
  $hl->configure(-browsecmd => [ \&hl_browse, $hl ]);
  $hl->header('create', 0, -itemtype => 'text', -text => "Date");
  $hl->columnWidth(0, -char => 16);
  $hl->header('create', 1, -itemtype => 'text', -text => "Team");
  $hl->columnWidth(1, -char => 26);
  $hl->header('create', 2, -itemtype => 'text', -text => "Reason");
  $hl->columnWidth(2, -char => 36);
  



  &load_penalties($hl);
  return $hl;
}

#---------------------------------------------------------------------
sub penalty_add {
  my $top = shift;
  my $curweek = shift;

  my $reason = "";
  my $date = "";
  my $plb;
  my $f = $top->Frame();
  $f->LabEntry(-label => "Reason: ", -textvariable => \$reason, 
			   -width => 30, labelPack => [ -side => 'left'])->pack(-side => 'left');
  
  my $add_but = $f->Button(-text => 'Add', -command => sub { 
	if ($reason ne '') {
	  $plb->insert('end',$date,$reason);
	  $reason = '';
	  $date = '';
	}
						   }
	);
  
  my $del_but = $f->Button(-text => 'Delete', -command => sub { 
	if ($reason ne '') {
	  $plb->delete('end',$date,$reason);
	  $reason = '';
	  $date = '';
	}
			 }
	);

}

#---------------------------------------------------------------------
sub penalty_edit {


}
#---------------------------------------------------------------------
sub penalty_del {


}

#---------------------------------------------------------------------
# Change the date of a match

sub match_reschedule {
  my $top = shift;
  my $w = shift;

  print "match_reschedule($w)\n";
  
  my $old_date = &week2date($w);
  my $new_date = "";

  my $dialog = $top->DialogBox(-title => "Reschedule Match Date",
                               -buttons => [ 'Ok', 'Cancel' ],
                               -default_button => 'Ok');
  $dialog->add('Label', -text => "Old Date: $old_date")->pack(-side => 'top');
  $dialog->add('Label', -text => "New Date (MM/DD/YYYY)")->pack(-side => 'left');
  $dialog->add('DateEntry', -textvariable => \$new_date, -width => 10)->pack(-side => 'left');
  
  my $ok = 1;
  while ($ok) {
    my $answer = $dialog->Show( );
    
    if ($answer eq "Ok") {
      print "New Date = $new_date\n";
      if ($new_date =~ m/^\d\d\/\d\d\/\d\d\d\d$/) {
        $ok--;
        my $num_matches = &updateweekdates($old_date,$new_date);
      }
      else {
        $top->messageBox(
			 -title => "Error!  Bad Date format.",
			 -message => "Error!  Bad Date format, please use MM/DD/YYYY.",
			 -type => 'Ok',
                        );
      }
    }
    elsif ($answer eq "Cancel") {
      print "No update made.\n";
      $ok--;
    }
  }
}

#---------------------------------------------------------------------
sub mk_results_rpt {
  my $w = shift;
  my $fh = shift;
  
  print "mk_results_rpt($w,FH)\n";

  my $d = &week2date($w);
  my ($h, $hc, $hs);
  my ($a, $ac, $as);

  my $ws = "$w ($d)";

  $^L = "";   # Turn off outputting formfeed when we get to a new page.
format RESULTS_TOP =

  Results:  Week @<<<<<<<<<<<<<<<<<<<<<<<
                $ws

.

format RESULTS =
      @<<<<<<<<<<<<<<<<<  @>  @<<<   vs  @<<<<<<<<<<<<<<<<<  @>  @<<<
          $h,                 $hs,$hc,       $a,                 $as,$ac
.
  

  $fh->format_name("RESULTS");
  $fh->format_top_name("RESULTS_TOP");
  $fh->autoflush(1);
  $fh->format_lines_left(0);

  for (my $i=1; $i <= $matches_per_week; $i++) {
    $h = $curmatch{$i}->{"HomeName"} . ":";
    $hs = $curmatch{$i}->{"HomeScore"};
    $hc = $curmatch{$i}->{"HomeCoed"} ? "(C)" : "(no)";
    
    $a = $curmatch{$i}->{"AwayName"} . ":";
    $as = $curmatch{$i}->{"AwayScore"};
    $ac = $curmatch{$i}->{"AwayCoed"} ? "(C)" : "(no)";
    write $fh;
  }
}

#---------------------------------------------------------------------
sub mk_standings_rpt {
  my $week = shift;
  my $fh = shift;

  print "mk_standings_rpt($week,FH)\n";

  my ($n, $team, $w, $t, $l, $f, $c, $gf, $ga, $pen, $pts, $d);

  $d = "$week, (" . &week2date($week) . ")";

format STANDINGS_TOP =

  Standings after Week @<<<<<<<<<<<<<<<<
                       $d                       

      # Team               W   T   L   F   C   GF   GA  P  Pts
      - ----------------- --- --- --- --- --- ---  --- --  ---
.

format STANDINGS =
      @ @<<<<<<<<<<<<<<<< @>> @>> @>> @>> @>> @>>  @>> @>  @>>
    $n,$team,           $w, $t, $l, $f, $c, $gf, $ga, $pen, $pts
.

  $fh->format_name("STANDINGS");
  $fh->format_top_name("STANDINGS_TOP");
  $fh->autoflush(1);
  $fh->format_lines_left(0);

  &update_standings($week);
  for (my $i = 1; $i <= $numteams; $i++) {
        $n    = $standings{$i}->{TEAMNUM};
        $team = $standings{$i}->{TEAM};
        $w    = $standings{$i}->{W};
        $t    = $standings{$i}->{T};
        $l    = $standings{$i}->{L};
        $f    = $standings{$i}->{F};
        $c    = $standings{$i}->{C};
        $gf   = $standings{$i}->{GF};
        $ga   = $standings{$i}->{GA};
	$pen  = $standings{$i}->{PCNT} || 0;
        $pts  = $standings{$i}->{PTS};

        write $fh;
  }  
}

#---------------------------------------------------------------------
sub mk_penalties {
  my $curweek = shift;
  my $fh = shift;

  print "mk_penalties($week,FH)\n";

  # Take hash of penalties per-team and convert into a date/team
  # sorted list.
  my @penalties;

  foreach my $m (sort byweektimefield @matches) {
	my $matchweek = $m->{"Week"};
	if ($matchweek <= $curweek) {
	  
	}
  }

}

#---------------------------------------------------------------------
sub mk_notes {
  my $fh = shift;

  print "mk_notes(FH)\n";

  print $fh "\n\n";
  print $fh "  Notes:\n";
  print $fh "\n\n";
}

#---------------------------------------------------------------------
# TODO - fix game start time in reports
sub mk_schedule_rpt {
  my $week = shift;
  my $fh = shift;

  print "mk_schedule_rpt($week,$fh)\n";

  $week++;
  my $nextweek = $week + 1;
  my $prevtime = "";
  my $prevfield = "";

  my ($time, $field, $home,$away);

  my $weekdate = &week2date($week);
  print "  Weekdate = $weekdate ($week)\n";
  my $nextweekdate = &week2date($nextweek);
  
  # TODO: Fix lookup of who is lining (if any) fields
  my $line_this_week = $lining_team{$week} || "<unknown>";
  my $line_next_week = $lining_team{$nextweek} || "<unknown>";

format SCHEDULE_TOP = 

  Schedule: @<<<<<<<<<<<<<<
             $weekdate

      Time    Field      Home                   Away
      ------  -------    ------------------     ------------------
.

format SCHEDULE =
      @<<<<<  @<<<<<<    @<<<<<<<<<<<<<<<<<     @<<<<<<<<<<<<<<<<<
      $time,  $field,    $home,                 $away
.

  $fh->format_name("SCHEDULE");
  $fh->format_top_name("SCHEDULE_TOP");
  $fh->autoflush(1);
  $fh->format_lines_left(0);

  foreach my $m (sort byweektimefield @matches) {
        if ($m->{"Week"} == $week) {
          $time = $m->{"Time"};
          $field = $m->{"Field"};
          $home = $teams[$m->{"Home"}];
          $away = $teams[$m->{"Away"}];
          write $fh;
        }
  }

format LINING_TOP =
.

format LINING =

  Lining:  @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
           $line_this_week;
           @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
           $line_next_week;


.

  if ($dolining) {
    print "Showing Lining in report...\n";
    $fh->format_name("LINING");
    $fh->format_top_name("LINING_TOP");
    $fh->autoflush(1);
    $fh->format_lines_left(0);
    write $fh;
  }
}

#---------------------------------------------------------------------
sub mk_key_rpt {
  my $fh = shift;
  print "mk_key_rpt(FH)\n";

  print $fh "\n";
  print $fh "Key\n";
  print $fh "------------\n";
  print $fh "#  - Team Number on Schedule\n";
  print $fh "W  - Wins\n";
  print $fh "T  - Ties\n";
  print $fh "L  - Losses\n";
  print $fh "C  - Coed Games\n";
  print $fh "Fo - Forfeits\n";
  print $fh "GF - Points For\n";
  print $fh "GA - Points Against\n";
  print $fh "Pts - Points for Standings\n";
  print $fh "\n";
  print $fh "See rules for how standings are calculated.\n";
  print $fh "\n";

}

#---------------------------------------------------------------------
# Make the weekly report, save it to a base file name passed in,
# adding in the date of week in YYYY-MM-DD format, or week-##
# depending on how called.

sub make_report {
  my $base_rpt_file = shift;
  my $ext = shift;

  print "make_report($base_rpt_file , $ext)\n";

  # Strip off .rpt if it exists.
  $base_rpt_file =~ s/\.rpt$//;

  my $week_date;
  my $file = "$base_rpt_file";
  if ($ext eq "YYYY-MM-DD") {
    my ($m,$d,$y) = split('/',&week2date($curweek));
    $file = $base_rpt_file . "-". sprintf("%04s-%02s-%02s",$y,$m,$d);
    print "  ext = YYYY-MM-DD, file = $file\n";
  }
  elsif ($ext eq "WEEK-##") {
    $file = "$base_rpt_file". "-$curweek";
    print "  ext = WEEK-##, file = $file\n";
  }
  
  $file .= ".rpt";
  
  if (!open(RPT, ">$file")) {
    warn "Error writing week $curweek report to $file: $!\n";
  }  
  else {
    &mk_results_rpt($curweek,\*RPT);
    &mk_standings_rpt($curweek,\*RPT);
    &mk_penalties($curweek,\*RPT);
    &mk_notes(\*RPT);
    &mk_schedule_rpt($curweek,\*RPT);
    &mk_key_rpt(\*RPT);
    close RPT;
    
    print "\nWrote game report to $file.\n";
  }
}

#---------------------------------------------------------------------
sub error_msg {

  my $msg = shift;

  print "MSG: $msg\n";
   
}

#---------------------------------------------------------------------
# Validates the data entered when building a new season.

sub validate {
  my $num = shift @_;
  my $start = shift @_;
  my $descrip = shift @_;
  my $tref = shift @_;
  my @t_entry = @$tref;

  if ($start eq "") {
    error_msg("Need a start date.");
    return 0;
  }
  elsif ($descrip eq "") {
    error_msg("Need a Season Description.");
    return 0;
  }
  else {
    my $cnt=0;
    foreach my $i (@t_entry) {
      $cnt++ if ($i->get ne "");
    }
    if ($cnt < $num) {
      error_msg("You entered $cnt team names, you need at least $num.");
      return 0;
    }
  }
  return 1;
}

#---------------------------------------------------------------------
sub inc_by_week {
  my $cur = shift;
  my ($y,$m,$d) = Decode_Date_US($cur);
  #print " inc_by_week($y/$m/$d) + 7d = ";
  ($y,$m,$d) = Add_Delta_Days($y,$m,$d,7);
  #print "  ($y/$m/$d)\n";
  $cur = sprintf("%02s/%02s/%4s",$m,$d,$y);
  return $cur;
}

#---------------------------------------------------------------------
sub check_holidays {
  my $cur = shift;
  my @hols = @_;

  my $ishol = 0;
  my ($cy,$cm,$cd) = Decode_Date_US($cur);
  foreach my $h (@hols) {
    my ($hy,$hm,$hd) = Decode_Date_US($h);
    if (Delta_Days($cy,$cm,$cd,$hy,$hm,$hd) == 0) {
      $ishol = 1;
    }
  }

  #print "check_holidays($cur) = $ishol\n";
  return $ishol;
}

#---------------------------------------------------------------------
# takes in a number of teams and a hash of team names and randomizes
# them.  This looks involved, but it's because I pass in a hash of
# entry values, which I want to randomize...

sub randomize_teams {
  my $ref = shift;

  my @entry = @$ref;
  my @h;

  print "randomize_teams( ... )\n" if $DEBUG;

  foreach my $e (@entry) {
    my $g = $e->get;
    push @h, $g unless $g eq "";
    $e->delete(0,length($g));
  }

  for (my $i = 5; $i>0; $i--) {
    @h = shuffle @h;
  }

  foreach my $e (@entry) {
    $e->insert(0,shift @h || "");
  }
}

#---------------------------------------------------------------------
# Takes input from the "Setup a new Season" window and generates a
# schedule which you need to approve.  FIXME: add summary and approval window.

sub generate_schedule {
  my $win = shift @_;
  my $num_ref = shift @_;
  my $num = $$num_ref;
  my $teamsref = shift @_;
  my @team_entry = @$teamsref;
  my $season_ref = shift @_;
  my $season = $$season_ref;
  my $start_date_ref = shift @_;
  my $start_date = $$start_date_ref;
  my $game_time_ref = shift @_;
  my $game_time = $$game_time_ref;
  my $practice = shift @_;
  my $do_lining = shift @_;
  my $hlb_ref = shift @_;
  my $hlb = $$hlb_ref;
  my $done_but_ref = shift @_;
  my $done_but = $$done_but_ref;
  
  # Validate inputs.  Should be in the Setup a New Season window, with
  # the 'Done' button disabled until all the required info is entered.
  
  print "Start Date: $start_date\n";
  if (&validate($num,$start_date,$season,$teamsref)) {
    
    my $n=1;
    foreach my $e (@team_entry) {
      my $g = $e->get;
      if ($g ne "" && $n <= $num) {
	print "  $n -> $g\n";
	$teams[$n++] = $g;
      }
    }
    
    # Get holidays, if any, to be skipped.
    my $hlb_cnt = $hlb->size;
    my @hols = $hlb->get(0,$hlb_cnt);
    print "Holidays:\n";
    foreach my $h (sort @hols) {
      print "  $h\n";
    }
    print "\n";
    
    my $cur_date = $start_date;
    
    # Check for a holiday on the start_date, not likely, but more
    # durable...  Do this in a loop, since we can have holidays
    # spanning multiple weeks.
    while (&check_holidays($cur_date, @hols)) {
      $cur_date = &inc_by_week($cur_date);
    }
    # Store Season Setup options
    $season{Lining} = $do_lining;
    $season{Description} = "Description";
    $season{Scrimmage} = $practice;
    $season{Playoff_Rounds} = "";
    $season{Number_Teams} = $num;

    # Initialize Matches array:
    print "Num teams = $num\n";
    my %template = %{$sched_template{$num}};

    # Actual week in schedule, template starts at zero for scrimmage
    # week, which is not scored, but is scheduled.  
    my $sched_week = 1;
    $sched_week = 0 if $first_match_scrimmage;
    
    foreach my $tmpl_wk (sort { $a <=> $b } keys %template) {
      next if ($tmpl_wk == 0 && $practice == 0);
      my @week_sched = @{$template{$tmpl_wk}};
      
      # Note!  Week Schedule assumes two fields and two games on each
      # field, along with a Bye and Lining column. 

      # Since we have SIX columns, pop off the last two, which are for
      # byes[5] and lining[6].  This is ugly and I should just change
      # the data structure.  TODO
      
      $lining_team{$week} = "";
      if ($do_lining) {
	$dolining = 1;
	my $is_lining = pop @week_sched;
	if ($is_lining ne "") {
	  $lining_team{$week} = $teams[$is_lining];
	}else {
	  $lining_team{$week} = "tbd";
	}
      }
      $bye_team{$week} = "" || "tbd";
      my $has_bye = pop @week_sched;
      if ($has_bye =~ m/^\d+$/) {
	$bye_team{$week} = $teams[$has_bye];
      }
      
      # What is our game start times?
      my($first_game_time,$second_game_time) = split(' & ', $game_time);
      
      # Now fill in the schedule for games this week.
      my $i = 0;
      my $game;
      print "Week: $sched_week : ";
      foreach my $match (@week_sched) {
	# Matches are #-#, if we don't see a -, it's something else
	if ($match =~ m/^\d+\-\d+$/) {
	  my ($home, $away) = split("-",$match);
	  print " $match ";
	  # copy our pre-setup match template and fill in the proper fields...
	  $game = { };
	  $game->{Date} = $cur_date;
	  $game->{OrigDate} = "";
	  $game->{Week} = $sched_week;
	  $game->{Home} = $home;
	  $game->{HomeScore} = "";
	  $game->{HomeCoed} = 0;
	  $game->{HomePoints} = 0;
	  $game->{Away} = $away;
	  $game->{AwayScore} = "";
	  $game->{AwayCoed} = 0;
	  $game->{AwayPoints} = 0;
	  $game->{Complete} = 0;
	  
	  # Template assumes two games at 7pm, then
	  # two at 8pm, using Fields 1 & 2, in that order. 
	  if ($i == 0 || $i == 2) {
	    $game->{Field} = "Field 1";
	  } else {
	    $game->{Field} = "Field 2";
	  }
	  if ($i == 0 || $i == 1) {
	    $game->{Time} = $first_game_time;
	  } else {
	    $game->{Time} = $second_game_time;
	  }
	  $i++; 
	  push @matches, $game;
	}
      }
      
      # Increment date by one week
      $cur_date = &inc_by_week($cur_date);
      while (&check_holidays($cur_date,@hols)) {
	$cur_date = &inc_by_week($cur_date);
      }
      $sched_week++;
    }
    
    # Need to put in a message box here which enables the 'Done'
    # button if it's all ok.  
    $done_but->configure(-state => 'normal');
  }
}

#---------------------------------------------------------------------
# This is where you hit the Done button once the generate_schedule()
# is finished it's work.

sub accept_schedule {

  my $top = shift;
  my $win = shift;
  my $desc = shift;
  $top->configure(title => $desc);
  $win->destroy;
  &load_datelist($match_datelist);
  &load_curmatch(1);
  &update_standings(1);
}

#---------------------------------------------------------------------
# add_holiday
sub add_holiday {

  my $win = shift;
  my $holsref = shift;
  my $holref = shift;
  my $hlb = shift;

  print "add_holiday()\n";
  
  my %hols = %$holsref;
  print "  Holiday: $holref\n";
}

#---------------------------------------------------------------------
# del_holiday
sub del_holiday {

  my $win = shift;
  my $holsref = shift;
  my $holref = shift;
  my $hlb = shift;

  print "del_holiday()\n";


}

#---------------------------------------------------------------------
sub rosters_edit {

}

#---------------------------------------------------------------------
sub rosters_mk_pdf {

}

#---------------------------------------------------------------------
sub rosters_show {

}

#---------------------------------------------------------------------
sub edit_season {
  
}

#---------------------------------------------------------------------
# Piss poor function name, FIXME.  

sub init_game_file {
  my $top = shift;

  my $widget;
  print "init_game_file()\n";

  my $game_time = $game_times[0];
  my $first_match_scrimmage = 0;
  my $teams_line_fields = 0;
  my $start_date = "";
  my $descrip = "";

  # Reset to nothing, since it's a new season.
  $game_file = "";

  my $win = MainWindow->new();
  $win->title("Setup a new Season");
  $win->configure(-height => 400,
                  -width => 800,
                  -background => 'white',
     );
  $win->geometry('-500-500');
  $win->optionAdd('*font', 'Helvetica 9');

  my $t;
  
  my $top_fr = $win->Frame();
  
  my $setup_fr = $top_fr->Frame(-borderwidth => 1, -relief => 'solid');
  my $team_fr = $top_fr->Frame(-borderwidth => 1, -relief => 'solid');
  my $sched_fr = $top_fr->Frame(-borderwidth => 1, -relief => 'solid');
  
  $setup_fr->pack(-side => 'left', -fill => 'y');
  $team_fr->pack(-side => 'left', -fill => 'y');
  $sched_fr->pack(-side => 'right', -fill => 'y');
  
  $t = $setup_fr->Frame(-borderwidth => 1, -relief => 'solid');
  $t->Label(-text => 'Season Description:')->pack(-side => 'top');
  $t->Entry(-textvariable => \$descrip, -width => 40)->pack(-side => 'bottom');
  $t->pack(-side => 'top', -fill => 'x');
  
  $setup_fr->BrowseEntry(-label => 'Num Teams',
			 -variable => \$numteams,
			 -width => 3,
			 -choices => \@teamcnt,
	)->pack(-side => 'top');
  
  $setup_fr->BrowseEntry(-label => 'Playoff Rounds',
			 -variable => \$playoff_rnd,
			 -width => 3,
			 -choices => \@playoff_rnds,
			)->pack(-side => 'top');
  
  $setup_fr->BrowseEntry(-label => 'Game Times',
			 -variable => \$game_time,
			 -width => 12,
			 -choices => \@game_times,
			)->pack(-side => 'top');
  
  $setup_fr->Checkbutton(-variable => \$first_match_scrimmage,
			 -text => "First Match for Scrimmage? ",
			)->pack(-side => 'top', -fill => 'x');
  
  $setup_fr->Checkbutton(-variable => \$teams_line_fields,
			 -text => "Teams Line Fields?",
			)->pack(-side => 'top', -fill => 'x');
  
  $t = $setup_fr->Frame(-borderwidth => 1, -relief => 'solid');
  $t->Label(-text => 'Start Date:')->pack(-side => 'left');
  $t->DateEntry(-textvariable => \$start_date)->pack(-side => 'left');
  $t->pack(-side => 'top', -fill => 'x');
  
  my %hols;
  my $holiday;
  my $tmf = $setup_fr->Frame(-borderwidth => 1, -relief => 'solid');
  $tmf->Label(-text => 'Holiday(s):')->pack(-side => 'left');
  $tmf->DateEntry(-textvariable => \$holiday)->pack(-side => 'left');
  
  # Create the listbox first, even though the add button gets packed
  # above it within the temp_middle_frame (tmf).  
  
  my $hlb = $setup_fr->Scrolled("Listbox", -scrollbars => "e",
				-height => 3, -selectmode => "single");
  
  my $mfab = $tmf->Button(-text => 'Add',-command => sub {
			    if ($holiday ne '') {
			      $hlb->insert('end',$holiday);
			      $holiday = '';
			    } }
			 );
  $mfab->pack(-side => 'left', -fill => 'x');
  
  my $mfdb = $setup_fr->Button(-text => 'Delete Holiday',-command => sub
			       { $hlb->delete($hlb->curselection) if $hlb->curselection;
				 $holiday = ''; }
			      );
  
  $tmf->pack(-side => 'top', -fill => 'x');
  $hlb->pack(-side => 'top', -fill => 'x');
  $mfdb->pack(-side => 'bottom', -fill => 'x');
  
  # Middle Frame: Teams
  my @teams_temp;
  my @entries;
  $team_fr->Label(-text => 'Team Names:')->pack(-side => 'top');
  for (my $i=1; $i <= $max_numteams; $i++) {
    my $f = $team_fr->Frame();
    $f->Label(-text => " $i ", -width => 6)->pack(-side => 'left');
    push @entries, $f->Entry(-textvariable => \$teams_temp[$i], 
			     -width => 25,
			    )->pack(-side => 'left');
    $f->pack(-side => 'top', -fill => 'x');
  }

  # Let's me be lazy and enter team names, then randomize them.
  my $rand_but = $team_fr->Button(-text => 'Randomize Teams', 
				  -command => [ \&randomize_teams, \@entries ],
				 );
  $rand_but->pack(-side => 'bottom', -fill => 'x');


  # Right Frame: Proposed Schedule
  my $sf = $sched_fr->Frame(-pady => 10, -border => 1);
  $sf->Label(-text => 'Proposed Schedule: ', 
			 -width => 30)->pack(-side => 'top');
  my $sl = $sf->Scrolled('HList', -scrollbars => 'ow', -columns => 8, 
						 -header => 1, -selectmode => 'single', -width
						 => 80,)->pack(-fill => 'x');
	
  $sl->header('create', 0, -itemtype => 'text', -text => 'Week');
  $sl->columnWidth(0, -char => 6);
  $sl->header('create', 1, -itemtype => 'text', -text => 'Date');
  $sl->columnWidth(1, -char => 10);
  $sl->header('create', 2, -itemtype => 'text', -text => 'Time');
  $sl->columnWidth(2, -char => 6);
  $sl->header('create', 3, -itemtype => 'text', -text => 'Field 1');
  $sl->columnWidth(3, -char => 8);
  $sl->header('create', 4, -itemtype => 'text', -text => 'Field 2');
  $sl->columnWidth(4, -char => 8);
  $sl->header('create', 5, -itemtype => 'text', -text => 'Field 1');
  $sl->columnWidth(5, -char => 8);
  $sl->header('create', 6, -itemtype => 'text', -text => 'Field 2');
  $sl->columnWidth(6, -char => 8);
  # Only for outdoor schedules..
  $sl->header('create', 7, -itemtype => 'text', -text => 'Lining');
  $sl->columnWidth(7, -char => 6);
  
  $sf->pack(-side => 'top', -fill => 'x');

  $top_fr->pack(-side => 'top', -fill => 'x');
  
  # Buttons at bottom of frame, one for Quit, one to Generate, one to
  # Accept proposed season.  Idea is that you can "Generate a schedule
  # multiple times, but only accept it once.  FIXME: Done needs work.
  
  my $but_fr = $win->Frame(-borderwidth => 1, -relief => 'solid');
  
  my $cancel_but = $but_fr->Button(-text => "Cancel", -command => [ $win => 'destroy' ]);
  my $done_but = $but_fr->Button(-text => "Done", -state => 'disabled',
				 -command => [ \&accept_schedule, $top, $win, \$descrip ]
				);
  
  my $gen_but = $but_fr->Button(-text => "Generate Schedule", 
				-command =>  [
					      \&generate_schedule, $win, \$numteams,
					      \@entries, \$descrip, \$start_date,
					      \$game_time, \$first_match_scrimmage,
					      \$teams_line_fields, \$hlb, \$done_but ] 
			       );
  
  # add in spacers...
  $but_fr->Frame(-borderwidth => 0, -relief => 'flat')->pack(-side => 'left', -expand => 1);
  $cancel_but->pack(-side => 'left', -fill => 'x');
  $but_fr->Frame(-borderwidth => 0, -relief => 'flat')->pack(-side => 'left', -expand => 1);
  $gen_but->pack(-side => 'left', -fill => 'x');
  $but_fr->Frame(-borderwidth => 0, -relief => 'flat')->pack(-side => 'left', -expand => 1);
  $done_but->pack(-side => 'right', -fill => 'x');
  $but_fr->Frame(-borderwidth => 0, -relief => 'flat')->pack(-side => 'right', -expand => 1);

  # Pack entire frame  of buttons...
  $but_fr->pack(-side => 'bottom', -fill => 'x');
}

#---------------------------------------------------------------------
# Accessor for date info stored in each match.  Returns and array of
# date(s) for all matches, sorted by weeknumber.  
sub get_match_dates {
  my %w;
  my @t;
  
  print " get_match_dates()\n";
  foreach my $m (sort byweektimefield @matches) {
    $w{$m->{'Week'}} = $m->{'Date'};
  }
  
  foreach (sort keys %w) {
    push @t, [ $_, $w{$_}, '          ' ];
  }

  # Sort before we return... not an ideal data structure, should be a
  # hash instead, indexed by week number.  
  return(sort { $a->[0] <=> $b->[0] } @t);
}

#---------------------------------------------------------------------
sub hl_browse {
  my $hl = shift;
  my ($path) = (@_);

  my $week = $hl->itemCget($path,0,-text);
  my $date = $hl->itemCget($path,1,-text);
  print "Path = $path (week = $week, date = $date)\n";
  &update_scores($week);
}

#---------------------------------------------------------------------
sub load_datelist {
  my $hl = shift;

  print "load_datelist()\n";
  
  $hl->delete('all');

  $dls_red = $hl->ItemStyle('text', -foreground => '#800000'); 
  $dls_blue = $hl->ItemStyle('text', -foreground => '#000080', -anchor=>'w'); 
  $dls_green = $hl->ItemStyle('text', -foreground => 'green', -anchor=>'w'); 
  $dls_done = $hl->ItemStyle('text', -background => 'lightgreen');
  
  foreach my $key (&get_match_dates) {
    print "  get_match_dates: $key\n";
    my $e = $hl->addchild("");
    $hl->itemCreate($e, 0, -itemtype=>'text', -text => $key->[0], -style=>$dls_red); 
    $hl->itemCreate($e, 1, -itemtype=>'text', -text => $key->[1], -style=>$dls_blue); 
    $hl->itemCreate($e, 2, -itemtype=>'text', -text => $key->[2], -style=>$dls_blue); 
    $hl->itemCreate($e, 3, -itemtype=>'text', -text => " ", -style=>$dls_blue); 
  }
}

#---------------------------------------------------------------------
sub init_datelist {
  my $top = shift;
  print "init_datelist()\n";

  my $hl = $top->Scrolled('HList', -scrollbars => 'ow',
                          -columns=> 4, -header => 1, 
			  -selectmode => 'single', -width => 46,
                         )->pack(-fill => 'x'); 
  $hl->configure(-browsecmd => [ \&hl_browse, $hl ]);
  $hl->header('create', 0, -itemtype => 'text', -text => "Week");
  $hl->columnWidth(0, -char => 6);
  $hl->header('create', 1, -itemtype => 'text', -text => "Date");
  $hl->columnWidth(1, -char => 16);
  $hl->header('create', 2, -itemtype => 'text', -text => "Old Date");
  $hl->columnWidth(2, -char => 16);
  $hl->header('create', 3, -itemtype => 'text', -text => "Type");
  $hl->columnWidth(3, -char => 6);

  &load_datelist($hl);
  return $hl;
}

#---------------------------------------------------------------------
sub init_standings {
  my $top = shift;

  print "init_standings()\n";

  &zero_standings(\%standings);
  
  my $f = $top->Frame;
  # Header
  my $ff = $f->Frame(-pady => 10, -border => 1);
  $ff->Label(-text => "#", -width => 2)->pack(-side => 'left');
  $ff->Label(-text => "Team", -width => 20, -anchor => 'w')->pack(-side => 'left');
  $ff->Label(-text => " W ", -width => 4)->pack(-side => 'left');
  $ff->Label(-text => " T ", -width => 4)->pack(-side => 'left');
  $ff->Label(-text => " L ", -width => 4)->pack(-side => 'left');
  $ff->Label(-text => " F ", -width => 4)->pack(-side => 'left');
  $ff->Label(-text => " C ", -width => 4)->pack(-side => 'left');
  $ff->Label(-text => " GF", -width => 4)->pack(-side => 'left');
  $ff->Label(-text => " GA", -width => 4)->pack(-side => 'left');
  $ff->Label(-text => "PEN", -width => 4)->pack(-side => 'left');
  $ff->Label(-text => "PTS", -width => 4)->pack(-side => 'left');
  $ff->Label(-text => "Rank", -width => 4)->pack(-side => 'left');
  $ff->pack(-side => 'top', -fill => 'x');

  # We have to go by the MAXIMUM number of teams that could play.
  foreach (my $x=1; $x <= $max_numteams; $x++) {
    my $ff = $f->Frame()->pack(-side => 'top', -fill => 'x');

    $ff->Label(-text => $x, -width => 2)->pack(-side => 'left');
    $ff->Label(-textvariable => \$standings{$x}->{TEAM}, -width => 20)->pack(-side => 'left');
    $standings{$x}->{TEAM} = $teams[$x];
    $ff->Label(-textvariable => \$standings{$x}->{W}, -width => 4)->pack(-side => 'left');
    $ff->Label(-textvariable => \$standings{$x}->{T}, -width => 4)->pack(-side => 'left');
    $ff->Label(-textvariable => \$standings{$x}->{L}, -width => 4)->pack(-side => 'left');
    $ff->Label(-textvariable => \$standings{$x}->{F}, -width => 4)->pack(-side => 'left');
    $ff->Label(-textvariable => \$standings{$x}->{C}, -width => 4)->pack(-side => 'left');
    $ff->Label(-textvariable => \$standings{$x}->{GF}, -width => 4)->pack(-side => 'left');
    $ff->Label(-textvariable => \$standings{$x}->{GA}, -width => 4)->pack(-side => 'left');
    $ff->Label(-textvariable => \$standings{$x}->{PCNT}, -width => 4)->pack(-side => 'left');
    $ff->Label(-textvariable => \$standings{$x}->{PTS}, -width => 4)->pack(-side => 'left');
    $ff->Label(-textvariable => \$standings{$x}->{RANK}, -width => 4)->pack(-side => 'left');
    $ff->pack(-side => 'top', -fill => 'x');
  }
  $f->pack(-side => 'top', -fill => 'x');
 }

#---------------------------------------------------------------------
# Used to both initialize and reset standings when updated.
sub zero_standings {

  if (@_) {
    my $ref = shift;
    for (my $t=1; $t <= $numteams; $t++) {
      foreach my $k (qw( W L T F C PTS GF GA RANK)) {
        $$ref{$t}->{$k} = 0;
      }
    }
  }
  else {
    for (my $t=1; $t <= $numteams; $t++) {
      foreach my $k (qw( W L T F C PTS GF GA RANK)) {
        $standings{$t}->{$k} = 0;
      }
    }
  }     
}

#---------------------------------------------------------------------
sub update_standings {

  my $week = shift;

  my %tmp;
  print "\nupdate_standings($week)\n";

  # Zero out the standings first
  &zero_standings(\%standings);
  &zero_standings(\%tmp);

  # Save the current week data back to @matches
  &save_curmatch($curweek);

  # Now go through all matches and figure out standings.
  foreach my $m (sort byweektimefield @matches) {
    my $matchweek = $m->{"Week"};
    if ($matchweek <= $curweek) {
	  # Do we have full scores recorded for this match yet?
      if ($m->{"Complete"}) {
		my $h = $m->{"Home"};
		my $a = $m->{"Away"};
		
		#print " Match Complete:  H: $h, A: $a\n";
		
		if ($m->{HomeScore} eq "F" && $m->{AwayScore} eq "F") {
		  #print "  Double Forfeit\n";
		  $tmp{$h}->{F}++;
		  $tmp{$a}->{F}++;
		}
		elsif ($m->{HomeScore} eq "F") {
		  #print "  Home forfeit\n";
		  $tmp{$h}->{F}++;
		  $tmp{$a}->{W}++;
		  $tmp{$a}->{GF} += 5;
		} 
	elsif ($m->{AwayScore} eq "F") {
	  #print "  Away Forfeit\n";
	  $tmp{$a}->{F}++;
	  $tmp{$h}->{W}++;
	  $tmp{$h}->{GF} += 5;
	}
		else {
		  # reset scores and such...
		  #print "   HS: $m->{HomeScore}, AS: $m->{AwayScore}\n";
		  
		  $tmp{$h}->{GF} += $m->{HomeScore};
		  $tmp{$a}->{GA} += $m->{HomeScore};
		  $tmp{$h}->{GA} += $m->{AwayScore};
		  $tmp{$a}->{GF} += $m->{AwayScore};
		  
		  if ($m->{HomeScore} < $m->{AwayScore}) {
			$tmp{$h}->{L}++;
			$tmp{$a}->{W}++;
		  }
		  elsif ($m->{HomeScore} == $m->{AwayScore}) {
			$tmp{$h}->{T}++;
			$tmp{$a}->{T}++;
		  }
		  elsif ($m->{HomeScore} > $m->{AwayScore}) {
			$tmp{$h}->{W}++;
			$tmp{$a}->{L}++;
		  }
		}
		
		$tmp{$h}->{C} += $m->{HomeCoed};
		$tmp{$a}->{C} += $m->{AwayCoed};
		
		#print "  HomePoints = $m->{HomePoints}\n";
		$tmp{$h}->{PTS} += $m->{HomePoints};
		$tmp{$a}->{PTS} += $m->{AwayPoints};
      }
    }
  }
  
  # Now sort %tmp and update %standings
  
  my $x = 1;
  foreach my $idx (sort {
    $tmp{$b}->{PTS} <=> $tmp{$a}->{PTS} 
      ||
    $tmp{$b}->{W} <=> $tmp{$a}->{W}
      ||
    $tmp{$b}->{L} <=> $tmp{$a}->{L}
      ||
    $tmp{$b}->{T} <=> $tmp{$a}->{T}
      ||
    ($tmp{$b}->{GF} - $tmp{$b}->{GA}) <=> ($tmp{$a}->{GF} - $tmp{$a}->{GA});
  } keys %tmp) {
    #print "$idx  $teams{$idx}   $tmp{$idx}->{PTS}\n";
    foreach my $k (qw( W L T F C PTS GF GA RANK)) {
      $standings{$x}->{$k} = $tmp{$idx}->{$k};
    }
    $standings{$x}->{TEAMNUM} = $idx;
    $standings{$x}->{TEAM} = $teams[$idx];
    $x++;
  }
}

#---------------------------------------------------------------------
# Save the current info in %curmatch back to the @match array.
sub save_curmatch {
  my $w = shift;

  # Save current week data....
  my $idx = 1;
  print "save_curmatch($w)\n";
  foreach my $m (sort byweektimefield @matches) {
    if ($m->{"Week"} == $w) {
      $m->{"HomePoints"} = $curmatch{$idx}->{"HomePoints"};
      $m->{"HomeScore"} = $curmatch{$idx}->{"HomeScore"};
      $m->{"HomeCoed"} = $curmatch{$idx}->{"HomeCoed"};
      #$curmatch{$idx}->{HomeScore} = "";
      
      $m->{"AwayPoints"} = $curmatch{$idx}->{"AwayPoints"};
      $m->{"AwayScore"} = $curmatch{$idx}->{"AwayScore"};
      $m->{"AwayCoed"} = $curmatch{$idx}->{"AwayCoed"};
      
      $m->{"Complete"} = $curmatch{$idx}->{"Complete"};
      $idx++;
    }
  }
}

#---------------------------------------------------------------------
sub clear_match_display {

  # Empty the Home and Away columns first, we have four matches per-week.
  for (my $i=1; $i <= $matches_per_week; $i++) {
	$curmatch{$i}->{"HomePoints"} = 0;
	$curmatch{$i}->{"HomeScore"} = 0;
	$curmatch{$i}->{"HomeCoed"} = 0;
	$curmatch{$i}->{"HomeName"} = "";
	$curmatch{$i}->{"AwayPoints"} = 0;
	$curmatch{$i}->{"AwayScore"} = 0;
	$curmatch{$i}->{"AwayCoed"} = 0;
	$curmatch{$i}->{"AwayName"} = "";

	$curmatch{$i}->{"Time"} = "";
	$curmatch{$i}->{"Field"} = "";
	$curmatch{$i}->{"Complete"} = 0;
	&chgcolor($notokcolor,$i);
  }
}

#---------------------------------------------------------------------
# Load the current match with data week $week

sub load_curmatch {
  my $week = shift;

  &clear_match_display;

  # Fill in the $curmatches with the proper match info
  my $curidx = 1;
  foreach my $m (sort byweektimefield @matches) {
    if ($m->{"Week"} == $week) {
      $curmatch{$curidx}->{"HomePoints"} = $m->{"HomePoints"};
      $curmatch{$curidx}->{"HomeScore"} = $m->{"HomeScore"};
      $curmatch{$curidx}->{"HomeCoed"} = $m->{"HomeCoed"};
      $curmatch{$curidx}->{"HomeName"} = $teams[$m->{"Home"}];
      
      $curmatch{$curidx}->{"AwayPoints"} = $m->{"AwayPoints"};
      $curmatch{$curidx}->{"AwayScore"} = $m->{"AwayScore"};
      $curmatch{$curidx}->{"AwayCoed"} = $m->{"AwayCoed"};
      $curmatch{$curidx}->{"AwayName"} = $teams[$m->{"Away"}];
      
      $curmatch{$curidx}->{"Time"} = $m->{"Time"};
      $curmatch{$curidx}->{"Field"} = $m->{"Field"};
      $curmatch{$curidx}->{"Complete"} = $m->{"Complete"};
      
      if ($m->{"Complete"}) {
		&chgcolor($okcolor,$curidx);
      } 
      else {
		&chgcolor($notokcolor,$curidx);
      }
      $curidx++;
    }
  }
}

#---------------------------------------------------------------------
sub update_scores {
  my $week = shift;

  print "\nupdate_scores($week)\n";
    
  if ($curweek != $week) {
    my $curidx;
    $weekdate = join("-", &week2date($week));
    
    &save_curmatch($curweek);
    
    &load_curmatch($week);
    # Reset the Current Week finally.
    $curweek = $week;
    &update_standings($curweek);
    # Require a save if we're exiting...
    $NeedSave = 0;
  }
}

#---------------------------------------------------------------------
sub init_scores {
  my $top = shift;
  my $week = shift;
  
  my $header = $top->Frame;
  my $hf = $top->Frame;
  my $scoreframe = $top->Frame;
  
  # Week dropdown and dates, getting rid of them...
  if (0) {
    $header->BrowseEntry(-label => 'Week:', -variable => \$week, 
			 -width => 2,
			 -choices => \@weeks,
			 -command => sub { &update_scores($week); },
			)->pack(-side => 'left');
    
    $weekdate=join("-",&week2date($week));
    print "Weekdate = $weekdate\n";
    $header->Label(-text => "Date: ", -width => 30, 
		   -anchor => 'e')->pack(-side=>'left');
    $header->Label(-textvariable => \$weekdate,
		   -width => 12)->pack(-side=>'left');
    
    $header->pack(-side => 'top', -fill => 'x');
  }
  
  # Headers
  
  $hf->Label(-text => "Time", -width => 6)->pack(-side => 'left');
  $hf->Label(-text => "Field", -width => 8)->pack(-side => 'left');
  $hf->Label(-text => "Home", -anchor => 'w', -width => 20)->pack(-side => 'left');
  $hf->Label(-text => "Score", -width => 10)->pack(-side => 'left');
  $hf->Label(-text => "Coed", -width => 4)->pack(-side => 'left');
  $hf->Label(-text => "Points", -width => 7)->pack(-side => 'left');
  
  $hf->Label(-text => "vs", -width => 8)->pack(-side => 'left');
  
  $hf->Label(-text => "Away", -anchor => 'w', -width => 20)->pack(-side => 'left');
  $hf->Label(-text => "Score",-width=>10)->pack(-side => 'left');
  $hf->Label(-text => "Coed",-width=>4)->pack(-side => 'left');
  $hf->Label(-text => "Points",-width=>6)->pack(-side => 'left');
  $hf->pack(-side => 'top', -fill => 'x');
  
  # Now create the pairs of games, currently maxes out at 4:
  
  foreach (my $m=1; $m <= $matches_per_week; $m++) {
    my $f = $top->Frame;
    my $w;
    
    $f->Label(-textvariable => \$curmatch{$m}->{"Time"}, -width => 6)->pack(-side => 'left');
    $f->Label(-textvariable => \$curmatch{$m}->{"Field"}, -width => 8)->pack(-side => 'left');
    $f->Label(-textvariable => \$curmatch{$m}->{HomeName}, -anchor =>
	      'w', -width => 20)->pack(-side => 'left');
    $f->BrowseEntry(-label => 'Score',
		    -variable => \$curmatch{$m}->{"HomeScore"},	
		    -width => 3,
		    -listwidth => 20,
		    -choices => \@scores,
		    -browsecmd => [ \&computepoints, $m,"Home" ],
		    # Only allow numbers or the letter F to be entered
		    -validate => 'key',
		    -validatecommand => sub { $_[0] =~ m/^(?:|F|\d+)$/; },
		   )->pack(-side => 'left');
    $f->Checkbutton( -variable => \$curmatch{$m}->{"HomeCoed"},
		     -command => [ \&computepoints, $m,"Home" ],
		   )->pack(-side => 'left');
    
    $w = $f->Label(-textvariable => \$curmatch{$m}->{"HomePoints"},
		   -background => $notokcolor,
		   -width => 6,
		  )->pack(-side => 'left');
    push @{$curmatch{$m}->{PointsLabels}}, $w;
    
    $f->Label(-text => "vs", -width => 8)->pack(-side => 'left');
    
    $f->Label(-textvariable => \$curmatch{$m}->{"AwayName"}, 
	      -anchor => 'w', -width => 20)->pack(-side => 'left');
    $f->BrowseEntry(-label => 'Score',
		    -variable => \$curmatch{$m}->{"AwayScore"},	
		    -width => 3,
		    -listwidth => 20,
		    -choices => \@scores,
		    -browsecmd => [ \&computepoints, $m,"Home" ],
		    # Only allow numbers or the letter F to be entered
		    -validate => 'key',
		    -validatecommand => sub { $_[0] =~ m/^(?:|F|\d+)$/; },
		   )->pack(-side => 'left');
    $f->Checkbutton( -variable => \$curmatch{$m}->{"AwayCoed"},
		     -command => [ \&computepoints, $m,"Home" ],
		   )->pack(-side => 'left');
    
    $w = $f->Label(-textvariable => \$curmatch{$m}->{"AwayPoints"},
		   -background => $notokcolor,-width => 6,
		  )->pack(-side => 'left');
    $f->pack(-side => 'top',-fill => 'x');
    push @{$curmatch{$m}->{PointsLabels}}, $w;
  }
  $top->pack(-side => 'top', -fill => 'x');
}


#---------------------------------------------------------------------
sub chgcolor {
  my $c = shift;
  my $i = shift;

  foreach my $w (@{$curmatch{$i}->{"PointsLabels"}}) {
    $w->configure(-background => "$c");
  }
}

#---------------------------------------------------------------------
sub load_game_file {
  my $file = shift;

  if (-f $file) {
    my $data = LoadFile($file);
    
    # Needs better error checking here!  We really only need the list
    # of teams and the matches to rebuild every thing else we use. 

    @teams = @{$data->{Teams}};
    @matches = @{$data->{Matches}};

    # Update the week display maybe?
    &load_datelist($match_datelist);
    &load_curmatch(1);
    &update_standings(1);
    
    # Update the rptfile name
    $rpt_file = $file;
    $rpt_file =~ s/\.tks$//;
    
    # Reset global default game_file
    $game_file = $file;

    return 1;
  }
  # Error, no file to load or some other error.  Needs Cleanup.
  return 0;
}

#---------------------------------------------------------------------
sub select_game_file {
  my $top = shift;
  my $file = shift;

  my $fs = $top->FileSelect(-directory => ".",
			    -filter => "*.tks",
			    -initialfile => $file,
			   );
  
  $fs->geometry("600x400");
  
  my $gf = $fs->Show;
  
  if (&load_game_file($gf)) {
    # Reset window Title to game_file
    $top->configure(title => $game_file);
  }
  else {
    print "Error loading.  Look in select_game_file()\n";
  }
}
  
#---------------------------------------------------------------------
sub save_game_file_as {
  my $top = shift;
  my $gf = shift;
  my $teamref = shift;
  my $matchref = shift;
  my $standingsref = shift;
  my $seasonref = shift;

  print "($gf, .... )\n";
  $gf = "new-season.tks"  if ($gf eq "");
  my $fs = $top->FileSelect(-directory => '.',
			    -filter => "*.tks",
			    -initialfile => $game_file,
	);
  $fs->geometry("600x400");
  my $savefile = $fs->Show;

  if ($savefile eq "") {
    
    print "Not saving the file...\n";
    return $gf;
  }
  else {
    if (!($savefile =~ m/^.*\.tks$/)) {
      $savefile .= ".tks";
    }  
    
    if (write_game_file($savefile,$teamref,$matchref,$standingsref,$seasonref)) {
      # Update our base report file name
      $rpt_file = $savefile;
      $rpt_file =~ s/\.tks$//;
      $top->configure(title => $gf);
      return $savefile;
    }
    else {
      return undef;
    }
  }
}
#---------------------------------------------------------------------
# double check we've got a valid game file to save to first...
sub save_game_file {
  my $top = shift;
  my $gf = shift;
  my $teamref = shift;
  my $matchref = shift;
  my $standingsref = shift;
  my $seasonref = shift;

  print "save_game_file($gf, .... )\n";
  if ($gf eq "") {
	&save_game_file_as($top,$gf,$teamref,$matchref,$standingsref,$seasonref);
  }
  else {
	&write_game_file($gf,$teamref,$matchref,$standingsref,$seasonref);
  }	
}

#---------------------------------------------------------------------
sub write_game_file {
  my $gf = shift;
  my $teamref = shift;
  my $matchref = shift;
  my $standingsref = shift;
  my $seasonref = shift;

  my $data = { Teams => $teamref,
	       Matches => $matchref,
	       Standings => $standingsref,
	       Season => $seasonref,
	       Version => $gf_version,
	     };
  
  print "DumpFile($gf, .... )\n";

  DumpFile($gf,$data);
  $NeedSave = 0;
}

#---------------------------------------------------------------------
sub playoffs_setup {

  # Select the number of rounds, 2 or 3
  # 

}

#---------------------------------------------------------------------
sub playoffs_score {


}

#---------------------------------------------------------------------
sub playoffs_report {

}

#---------------------------------------------------------------------
sub load_config {


}

#---------------------------------------------------------------------
# Implements the rules of the league.  Could be make more generic with
# a rules configuration file at some point.  
#
# TODO: Needs to have magic constants pulled out and proper names
# applied.

sub computepoints {

  my $idx = shift;
  my $us = shift;

  print "computepoints($idx,$us)\n";
  my ($ourscore,$ourcoed,$ourpts,$them,$theirscore,$theircoed);

  #print "scoring the match...\n";
  my $hs = $curmatch{$idx}->{"HomeScore"};
  my $hc = $curmatch{$idx}->{"HomeCoed"};
  my $as = $curmatch{$idx}->{"AwayScore"};
  my $ac = $curmatch{$idx}->{"AwayCoed"};
  
  #print "Scores:  $hs ($hc) : $as ($ac)\n";
  
  # Now we score the damn thing, big ugly state table...

  # Check for two empty scores, or one numeric and one empty
  if ($hs eq "" and $as eq "")  {
    $curmatch{$idx}->{"HomePoints"} = 0;
    $curmatch{$idx}->{"AwayPoints"} = 0;
	$curmatch{$idx}->{"Complete"} = 0;
    &chgcolor($notokcolor,$idx);
	$NeedSave = 1;
  }
  # Double Forfeit = no points for anyone.
  elsif ($hs eq "F" and $as eq "F") {
	#print "Double Forfeit\n";
	$curmatch{$idx}->{"HomePoints"} = 0;
	$curmatch{$idx}->{"HomeCoed"} = 0;
	$curmatch{$idx}->{"AwayPoints"} = 0;
	$curmatch{$idx}->{"AwayCoed"} = 0;
	$curmatch{$idx}->{"Complete"} = 1;
	&chgcolor($okcolor,$idx);
	$NeedSave = 1;
  }
  elsif ($hs eq "F" and $as =~ m/^$|\d+/) {
	#print "Home Forfeit.\n";
	$curmatch{$idx}->{"HomePoints"} = 0;
	$curmatch{$idx}->{"HomeCoed"} = 0;
	$curmatch{$idx}->{"AwayScore"} = "";
	$curmatch{$idx}->{"AwayPoints"} = 6 + $curmatch{$idx}->{"AwayCoed"};
	$curmatch{$idx}->{"Complete"} = 1;
	&chgcolor($okcolor,$idx);
	$NeedSave = 1;
  }
  elsif ($as eq "F" and $hs =~ m/^$|\d+/) {
	#print "Away Forfeit.\n";
	$curmatch{$idx}->{"HomePoints"} = 6 + $curmatch{$idx}->{"HomeCoed"};
	$curmatch{$idx}->{"AwayPoints"} = 0;
	$curmatch{$idx}->{"AwayCoed"} = 0;
	$curmatch{$idx}->{"HomeScore"} = "";
	$curmatch{$idx}->{"Complete"} = 1;
	&chgcolor($okcolor,$idx);
	$NeedSave = 1;
  }
  elsif ($hs eq "" and $as =~ /\d+/) {
	$curmatch{$idx}->{"HomePoints"} = 0;
	$curmatch{$idx}->{"AwayPoints"} = 0;
	$curmatch{$idx}->{"Complete"} = 0;
	&chgcolor($notokcolor,$idx);
	$NeedSave = 1;
  }	
  elsif ($as eq "" and $hs =~ /\d+/) {
	$curmatch{$idx}->{"HomePoints"} = 0;
	$curmatch{$idx}->{"AwayPoints"} = 0;
	$curmatch{$idx}->{"Complete"} = 0;
	&chgcolor($notokcolor,$idx);
	$NeedSave = 1;
  }	
  elsif ($hs > $as) {
	#print "Home Wins.\n";
	$curmatch{$idx}->{"HomePoints"} = 6 + $curmatch{$idx}->{"HomeCoed"};
	$curmatch{$idx}->{"AwayPoints"} = 2 + $curmatch{$idx}->{"AwayCoed"};
	$curmatch{$idx}->{"Complete"} = 1;
	&chgcolor($okcolor,$idx);
	$NeedSave = 1;
  }
  elsif ( $hs == $as ) {
	#print "Tie.\n";
	$curmatch{$idx}->{"HomePoints"} = 4 + $curmatch{$idx}->{"HomeCoed"}; 
	$curmatch{$idx}->{"AwayPoints"} = 4 + $curmatch{$idx}->{"AwayCoed"};
	$curmatch{$idx}->{"Complete"} = 1;
	&chgcolor($okcolor,$idx);
	$NeedSave = 1;
  }
  elsif ( $hs < $as ) {
	#print "Away Wins.\n";
	$curmatch{$idx}->{"HomePoints"} = 2 + $curmatch{$idx}->{"HomeCoed"}; 
	$curmatch{$idx}->{"AwayPoints"} = 6 + $curmatch{$idx}->{"AwayCoed"};
	$curmatch{$idx}->{"Complete"} = 1;
	&chgcolor($okcolor,$idx);
	$NeedSave = 1;
  }
}


#---------------------------------------------------------------------
sub mkbuttons {
  my $top = shift;

  my $buttons = $top->Frame;
  my $butspace = $buttons->Frame->pack(-side => 'left', 
									   -fill => 'both',
									   -expand => 'yes');
  
  $butspace = $buttons->Frame->pack(-side => 'left', 
									-fill => 'both',
									-expand => 'yes');
  
  $buttons->Button(-text => 'Quit',-command => sub{ &cleanup_and_exit($top,$game_file)},
	)->pack(-side => 'left', -expand =>'yes');
  
  $buttons->Frame(-width => 5)->pack(-side => 'left', -expand =>'yes');
  
  $buttons->Button(-text => 'Load',-command => sub { &select_game_file($top,$game_file); },
	)->pack(-side => 'left', -expand =>'yes');
  
  $buttons->Button(-text => 'Save',-command => sub { 
	&save_curmatch($curweek);
	&save_game_file($top,$game_file,\@teams,\@matches,\%standings,\%season);
				   },
	)->pack(-side => 'left', -expand =>'yes');
  
  $buttons->Button(-text => 'Save As',-command => sub { 
	&save_curmatch($curweek);
	$game_file = &save_game_file_as($top,$game_file,\@teams,\@matches,\%standings,\%season);
				   },
	)->pack(-side => 'left', -expand =>'yes');
  
  $buttons->Frame(-width => 5)->pack(-side => 'left', -expand =>'yes');
  
  $buttons->Button(-text => 'Update Standings',-command => sub{ &update_standings($curweek) },
	)->pack(-side => 'left', -expand =>'yes');
  
  $buttons->Button(-text => 'Make Report',-command => sub{ &make_report($rpt_file,"YYYY-MM-DD") },
	)->pack(-side => 'left', -expand =>'yes');
  
  $buttons->pack(-side => 'bottom');

}


#---------------------------------------------------------------------
sub roster_email_pdf {
  my $team = shift;

}

#---------------------------------------------------------------------
# Creates a PDF file which can be emailed to manager(s) for each team
# to be given to refs at start of game.  Needs a better function name
# though. 

sub roster_mk_pdf {

  my $save_dir = shift @_;
  my $team = shift @_;
  my $home = shift @_;
  my $away = shift @_;
  my $week = shift @_;

  my $pdf = new PDF::API2;
  $pdf->mediabox('Letter');
  my $page = $pdf->page;
  my $font = $pdf->corefont("Helvetica-Bold");

  $pdf->info(
	     'Author'       => "John Stoffel, DSL Secretary",
	     #'CreationDate' => "D:20130404180000",
	     #'ModDate'      => "D:YYYYMMDDhhmmssOHH'mm'",
	     'Creator'      => "tk-score6.pl",
	     'Producer'     => "PDF::API2",
	     'Title'        => "Team Roster: $team",
	     'Subject'      => "",
	     'Keywords'     => "DSL Soccer Roster"
	    );
  
  my $header = $page->text();
  $header->font($font, 20);
  $header->translate(20,750);
  $header->text("Digital Soccer League - 2013 Outdoor Season");
  
  $header->translate(20,715);
  $header->text("Game Roster: $team");
  
  my $header_props = { font => $pdf->corefont("Helvetica-Bold"),
		       font_size => 14,
		     };					 
  
  # some data to layout
  my $game =[
	     [ "Week", "Home:", "Away:", "Date", "Time",  "Field 1" ],
	     [ "$week", "$home",  "$away", "4/31/2013", "6pm", "Field 1" ],
	    ];
  
  my $roster = [
		[ "Num", "Last, First", "Mass Soccer ID", "Playing?" ],
		[ "16", "Stoffel, John",  "12345678", "  Yes        No  "],
		[ "12", "Leidel, Ryan",   "32345566", "  Yes        No  "],
		[ "16", "Kiernan, Jason", "34567834", "  Yes        No  "],
		[ "16", "Kiernan, Jason", "34567834", "  Yes        No  "],
		[ "16", "Kiernan, Jason", "34567834", "  Yes        No  "],
		[ "16", "Kiernan, Jason", "34567834", "  Yes        No  "],
		[ "16", "Kiernan, Jason", "34567834", "  Yes        No  "],
		[ "16", "Kiernan, Jason", "34567834", "  Yes        No  "],
		[ "  ", "              ", "        ", "  Yes        No  "],
		[ "  ", "              ", "        ", "  Yes        No  "],
		[ "  ", "              ", "        ", "  Yes        No  "],
		[ "  ", "              ", "        ", "  Yes        No  "],
	       ];
  
  # build the table layout
  my $gtable = PDF::Table->new;
  
  $gtable->table(
		 # required params
		 $pdf, $page, $game,
		 -x  => 20,
		 -start_y => 680,
		 -next_y => 700,
		 -start_h => 300,
		 -next_h => 500,
		 # some optional params
		 -w => 570,
		 -padding => 5,
		 -padding_right => 10,
		 -background_color_odd => "lightgray",
		 -background_color_even => "white",
		 -header_props => $header_props,
		);
  
  my $rtable = PDF::Table->new;
  $rtable->table(
		 # required params
		 $pdf, $page, $roster,
		 -x  => 20,
		 -start_y => 600,
		 -next_y => 700,
		 -start_h => 300,
		 -next_h => 500,
		 # some optional params
		 -w => 570,
		 -padding => 5,
		 -padding_right => 10,
		 -background_color_odd => "lightgray",
		 -background_color_even => "white",
		 -header_props => $header_props,
		);

  my $file = "$save_dir/$team-roster.pdf";
  $file =~ s/(\s+)/_/g;
  $pdf->saveas($file);
  print "Wrote $team Roster to $file\n\n";
  $pdf->end;
}

#---------------------------------------------------------------------
sub schedule_view {


}

#---------------------------------------------------------------------
sub parseopts {

  #&debug("parseopts()\n");

  GetOptions(
	     'D:i'   => \$DEBUG,
	     'f=s'   => \$game_file,
	     'i'     => \$initialize_season,
	     'h'     => \$prog_help,
	     'r'     => \$do_report,
	    ) or pod2usage(2);
  pod2usage(2) if ($#ARGV < -1);
  pod2usage(1) if $prog_help;
  pod2usage(-exitstatus => 0, -verbose => 2) if $man;
}

# Set the report filename based on our game_file name.
$rpt_file = $game_file;
$rpt_file =~ s/\.tks$//;


#---------------------------------------------------------------------
# If asked to generate a report, don't setup the windows at all.  
#---------------------------------------------------------------------

# Parse command line options.
&parseopts;

if ($do_report && $game_file) {
  &load_game_file($game_file);
  &make_report();
  &Tk::exit;
}

#---------------------------------------------------------------------
# MAIN SETUP, turn into a function someday!
#---------------------------------------------------------------------
my $top = MainWindow->new;
$top->configure(-title => "No game file loaded",
                -height => 400,
                -width => 1000,
                -background => 'white',
               );
$top->geometry('-300-300');
$top->optionAdd('*font', 'Helvetica 9');

# Menu Bar of commands
my $mbar=$top->Menu();
$top->configure(-menu => $mbar);
my $m_season=$mbar->cascade(-label=>"~Season", -tearoff => 0);
my $m_match=$mbar->cascade(-label=>"~Match", -tearoff => 0);
my $m_penalty=$mbar->cascade(-label=>"~Penalty", -tearoff => 0);
my $m_playoffs=$mbar->cascade(-label=>"Playoffs", -tearoff => 0);
my $m_rosters=$mbar->cascade(-label=>"Rosters", -tearoff => 0);
my $m_teams=$mbar->cascade(-label=>"Teams", -tearoff => 0);
my $m_schedule=$mbar->cascade(-label=>"Schedule", -tearoff => 0);
my $m_help=$mbar->cascade(-label =>"~Help", -tearoff => 0);

#---------------------------------------------------------------------
# Season Menu
$m_season->command(-label => '~New     ', -command => sub { 
		     &init_game_file($top); },
		  );
$m_season->command(-label => '~Open    ', -command => sub {
		     &select_game_file($top,$game_file);
		   },
		  );
$m_season->command(-label => 'Edit    ', -command => [ \&edit_season, \%season ],);
$m_season->command(-label => '~Save    ', -command => sub { 
		     &save_curmatch($curweek);
		     &save_game_file($top,$game_file,\@teams,\@matches,\%standings,\%season);
		   },
		  );
$m_season->command(-label => '~Save As ', -command => sub { 
		     &save_curmatch($curweek);
		     $game_file = &save_game_file_as($top,$game_file,\@teams,\@matches,\%standings,\%season);
			   },
  );
$m_season->separator();
$m_season->command(-label => '~Update Standings', -command => sub {
		     &update_standings($curweek) },
		  );
$m_season->separator();
$m_season->command(-label => '~Report  ', -command => sub {
		     &make_report($rpt_file,"YYYY-MM-DD") },
		  );
$m_season->separator();
$m_season->command(-label => '~Quit    ', -command => sub{ &cleanup_and_exit($top,$game_file)},
  );

#---------------------------------------------------------------------
# Match Menu
$m_match->command(-label => 'Reschedule', -command => sub {
		    &match_reschedule($top,$curweek);},
		 );

#---------------------------------------------------------------------
# Penalty Menu
$m_penalty->command(-label => 'Add', -command => sub {
  &penalty_add($top,$curweek);},
  );
$m_penalty->command(-label => 'Edit', -command => sub {
  &penalty_edit($top,$curweek);},
  );
$m_penalty->command(-label => 'Remove', -command => sub {
  &penalty_del($top,$curweek);},
  );

#---------------------------------------------------------------------
# Playoffs Menu
$m_playoffs->command(-label => 'Setup', -command => sub {
  &playoffs_setup($top,$curweek);},
  );
$m_playoffs->command(-label => 'Score', -command => sub {
  &playoffs_score($top,$curweek);},
  );
$m_playoffs->command(-label => 'Report', -command => sub {
  &playoffs_reports($top,$curweek);},
  );


#---------------------------------------------------------------------
# Rosters Menu
$m_rosters->command(-label => 'New', -command => sub {
  &rosters_edit($top,$curweek);},
  );
$m_rosters->command(-label => 'Edit', -command => sub {
  &rosters_edit($top,$curweek);},
  );
$m_rosters->command(-label => 'View', -command => sub {
  &rosters_show($top,$curweek);},
  );
$m_rosters->command(-label => 'Export to PDF', -command => sub {
  &rosters_mk_pdf($top,$curweek);},
  );
$m_rosters->command(-label => 'Export to CSV', -command => sub {
  &rosters_mk_csv($top,$curweek);},
  );
$m_rosters->command(-label => 'Mail to Managers', -command => sub {
  &rosters_mailto_managers($top,$curweek);},
  );


#---------------------------------------------------------------------
# Teams Menu
$m_teams->command(-label => 'View', -command => [ \&teams_view, $top, @teams ],);

#---------------------------------------------------------------------
# Schedule Menu
$m_schedule->command(-label => 'View', -command => [ \&schedule_view, $top, @matches ],);

#---------------------------------------------------------------------
# Help Menu
$m_help->command(-label => 'Version');
$m_help->separator;
$m_help->command(-label => 'About');

# Scores are up top, Week display and standings below, side by side.

my $scoreframe=$top->Frame(-border => 2, -relief => 'groove');
&init_scores($scoreframe,$week);
&update_scores($week);
$scoreframe->pack(-side => 'top', -fill => 'x');

my $bottomframe = $top->Frame();

my $datesframe = $bottomframe->Frame(-border => 2, -relief => 'groove');
$match_datelist = &init_datelist($datesframe);
$datesframe->pack(-side => 'left', -fill => 'x');

my $standingsframe = $bottomframe->Frame(-border => 2, -relief => 'groove');
&init_standings($standingsframe);
$standingsframe->pack(-side => 'right', -fill => 'y');

$bottomframe->pack(-side => 'top', -fill => 'x');


&MainLoop;




#---------------------------------------------------------------------
# Change Log
#---------------------------------------------------------------------
#
# V 1.5 - 2013-03-03
#
# - finally started using a changelog
# - improved report generation to using game date
#
# 2013/04/04 - v1.6
# - started support for outdoor season
#   - 9 team schedule, with lining and bye columns
#   - updated 8 team schedule with empty bye and lining columns
#   - initial support for PDF format rosters using PDF::API2 and PDF::Table
#   - updated display for proper column support and report generation.


#---------------------------------------------------------------------
# POD docs... using pod2usage

__END__

=head1 tk-score

=head1 SYNOPSIS

tk-score [options] 

  Options:
     -D [#]                debugging
     -f <file>             which .tks season file to load
     -h                    this help
     -i                    initialize a new season.
     -v                    verbose
     
=head1 OPTIONS

=over 8

=item B<-f file>

Tells which .tks file holding a season to load.

=back

=head1 DESCRIPTION

B<tk-score> is a tool to help manage and score a soccer (football)
league over a season.  

=cut

=head1 AUTHOR

John Stoffel
john@stoffel.org
