#!/usr/local/bin/perl
use strict;
use warnings;
use Data::Dumper;
use Benchmark qw(:hireswallclock);    # :hireswallclock -> for hi-res timing (microseconds)

my($DEBUG) = 1;                       # Global to toggle logging to STDOUT
my($t0) = Benchmark->new;

my %seats;
my($rows,$cols);
$rows = 3;
$cols = 11;

initSeatingChart($rows,$cols);        # Build data structure
my(@scored) = rankSeats();            # Get sorted array of best->worst 'SCORE'

my($reqFlg) = 0;                      # Request data flag
while(<>){                            # Each line of input until EOF
  chomp($_);                          # Strip crlf
  if(!$reqFlg){                       # 1st line of file (potentially reserved seats)
    setReserved($_);                  # Process reserved seats
    $reqFlg = 1;                      # Set request data flags
  } else {
    findSeats($_);                    # Process # Seat request
  }
}
print "\nRemaining Available Seats: ".getRemSeats()."\n\n";

# - Benchmark testing for determining best method of looping
my($t1) = Benchmark->new;
my($td) = timediff($t1, $t0);
logger("the code took: ".timestr($td)."\n");

# -
# Check all possible combinations of requested block using key
# -
sub chkCombos {
  my($key,$reqSeatCnt) = @_;                                          # Key in common, number of requested seats
  my($keyRow,$keyCol) = split(",",$key);                              # Split out row/column key
  my(%combos) = ();                                                   # store key combos and total score
  my($bkr) =  ($keyCol-($reqSeatCnt-1)) > 0 
                ? ($keyCol-($reqSeatCnt-1)) : "0";                    # Column can not be less than 0
  my($ekr) =  ($keyCol+($reqSeatCnt-1)) < 11 
                ? ($keyCol+($reqSeatCnt-1)) : "11";                   # Column can not be more than highest column
  my(@dataArr) = ($bkr .. $ekr);                                      # Start range  .. End range of possible seat block
  my(%seatOptions) = ();
  for(my $i = 0; $i <= $#dataArr; $i++){
    my($blockScore) = 0;                                              # Total block score
    if(defined($dataArr[$i+($reqSeatCnt-1)])){                        # Last possible element in block is not outside scope of array range
      my($sk) = $dataArr[$i];                                         # Starting column key of possible block of seats
      for(my $j = 0; $j <= $reqSeatCnt-1; $j++){
        my($tmpCol) = $sk+$j;
        logger("Possible Column: ".$tmpCol."\n");
        if(defined($seats{$keyRow.",".$tmpCol})){                     # Seat exists
          logger("seat exists: ".$keyRow.",".$tmpCol."\n");
          if($seats{$keyRow.",".$tmpCol}{STATUS} ne "X"){             # Seat is available
            $blockScore += $seats{$keyRow.",".$tmpCol}{SCORE};        # Add total score to block total
            if($j == ($reqSeatCnt-1)){                                # Last iteration (full block found)
              $seatOptions{$keyRow.",".$sk} = $blockScore;            # Set possible block total score
            }
          } else { last; }
        } else { last; }
      }
    }
  }
  logger("SEAT OPTIONS\n");
  logger(Dumper(\%seatOptions));
  logger("\n");
  my(@res);
  if(%seatOptions){
    logger("Atleast 1 valid block of seats found\n");
    my(@scores) = sort { $seatOptions{$a} <=> $seatOptions{$b} } keys %seatOptions; # Sort possible blocks by lowest value
    logger("SCORES:\n");
    foreach(@scores){
      logger($_."\n");
    }
    if(@scores){
      my($blockKey) = $scores[0];                               # Key of first seat in seat block
      logger("BK: $blockKey\n");
      # Create block of keys
      my($row,$col) = split(",",$blockKey);                     # Split out row/column key
      for(my $c = 0; $c <= $reqSeatCnt-1; $c++){                # Find requested number of seats in a row
        my $pk = $row.",".($col+$c);                            # Build each seat key for block
        logger("Seat in block: ".$pk."\n");
        push(@res,$pk);                                         # Add seats from block to result array
      }
    }
    return \@res;                                               # Resulting block of seat keys (best available block)
  } else {
    return 0;
  }
}

# - 
# Find best block of seats given a certain number of seats as a request
#  @PARAM: 
#   - $reqSeatCnt Number of seats requested
# -
sub findSeats {
  my($reqSeatCnt) = shift;                          # count asking for
  my($chosen);                                      # Result list scalar
  # Start searching at best available seat
  print "Request for: ${reqSeatCnt} seat(s)\n";
  foreach my $k (@scored){                          # Each available seat by best 'SCORE'
    logger("Trying ".$k." --> SCORE: ".$seats{$k}{SCORE}."\n");
    my($row,$col) = split(",",$k);                  # Split key into row and column parts
    $chosen = lookDirection($row,$col,$reqSeatCnt); # Try to find available seats for current key
    if($chosen){                                    # Found number of requested seats available
      logger("Done: Found match for $reqSeatCnt\n");
      print "Found seat(s):\n";
      foreach(@$chosen){                            # De-referenced result list
        my($key) = $_;
        $seats{$key}{'STATUS'} = "X";               # Mark seat as reserved
        @scored = grep {!/$key/} @scored;           # Remove newly taken seat from sorted score array
        print $key."\n";
      }
      print "\n";
      logger(print "---------------------\n\n"); 
      last; 
    }
  }
  if(!$chosen){                                     # No available seats found
    print "Not Available\n";
    logger("---------------------\n\n"); 
  }
}

# -
# Look a direction based on the seating chart grid
#  -> Look to the 'left' for primary seat keys that reside to the left of front-center          (faster)
#  -> Look to the 'right' for primary seat keys that reside to the right of front-center        (faster)
#  -> Look both directions for primary seat keys that reside in the same column as front-center (slowest)
#  -> By looking only to one direction we are potentially cutting the number of iterations in our loop by 50%
# @PARAM:
#  Row, col, # of requested seats
# -
sub lookDirection {
  my($row,$col,$reqSeatCnt) = @_;
  my($cc) = int(($cols/2)+1);                   # Center column
  my(@res);                                     # Resulting seat keys
  if($col == $cc){                              # Key column is the center column
    # Side step issue with assigning block that is not best
    # if key seat isnt a start/end seat, this is possible
    # - Switch between lookleft and lookright - track current iteration each time, compare values 
    logger("LookingBothWays($row,$col)\n");
    my($pk) = $row.",".$col;
    my($sk) = chkCombos($pk,$reqSeatCnt);       # Special method of looking both directions in seating row
    if($sk){
      @res = @$sk;                              # De-referenced result list
    } else {
      logger("Unavailble seat: $pk\n");
      return 0;
    }
  } elsif($col > $cc){                          # Seat is right of center
    # - Looking right direction - #
    logger("LookingRight($row,$col)\n");
    for(my $c = 0; $c <= $reqSeatCnt-1; $c++){  # Find requested number of seats in a row
      if(($col+$c) < $cols){
        my $pk = $row.",".($col+$c);
        if($seats{$pk}{'STATUS'} eq "X"){
          logger("Unavailble seat: $pk\n");
          return 0;
        } else {
          logger("Available seat: $pk\n");
          push(@res,$pk);  
        }
      } else {
        logger("End of row encountered: Not enough space for $reqSeatCnt seats\n");
        return 0;
      }
    }
  } else {                                      # Seat is left of center
    # Looking left direction
    logger("LookingLeft($row,$col)\n");
    for(my $c = 0; $c <= $reqSeatCnt-1; $c++){  # Find requested number of seats in a row
      if(($col-$c) > 0){
        my $pk = $row.",".($col-$c);
        if($seats{$pk}{'STATUS'} eq "X"){
          logger("Unavailble seat encountered: $pk\n");
          return 0;
        } else {
          logger("Available seat: $pk\n");
          push(@res,$pk);  
        }
      } else {
        logger("End of row encountered: Not enough space for $reqSeatCnt seats\n");
        return 0;
      }
    }
  }
  return \@res;                                 # Return reference to resul seat key list
}


# -
# Initialize seating chart
# @PARAM: 
#   Row count
#   Column count
# -
sub initSeatingChart {
  my($rows,$cols) = @_;
  my(@r) = (1...$rows);
  my(@c) = (1...$cols);
  my($fc) = "1,".int(($cols/2)+1);                  # Create front-center seat pair
  logger("Front Center: ".$fc."\n\n");
  foreach(@r){                                      # Each defined row
    my($row) = $_;
    foreach(@c){                                    # Each defined column
      my($col) = $_;
      $seats{$row.",".$col} = ({                    # Hash element for each seat in venue
        "STATUS" => "O",                            # Init status of 'open' chnage to " " later
        "SCORE"  => getSeatScore($fc,$row.",".$col)
      });
    }
  }
}

# -
# Takes a string (space separated R#C#)
# - 
sub setReserved {
  my(@reserved) = split(' ',shift);         # Split seats on space separator
  foreach(@reserved){                       # Each reserved seat (R#C#)
    $_ =~ /R(\d+)C(\d+)/;                   # Capture group to split row and col integers
    my($row,$col) = ($1,$2);                # First,Second capture
    $seats{$row.",".$col}
         {"STATUS"} = "X";                  # Indicate reserved
    @scored = grep {!/$row,$col/} @scored;  # Remove reserved seat key from sorted array 
  }
}

# -
# Return array of keys sorted from best->worst
# -
sub rankSeats {
  my @scored = sort { $seats{$a}{SCORE} <=> $seats{$b}{SCORE} or $a cmp $b}  keys %seats; # keys sorted on 'SCORE' from best->worst
  return @scored;
}

# -
# Count number of remaining available seats
# -
sub getRemSeats {
  return scalar @scored;
}

# -
# Returns Manhattan Distance for seat pairing 
# in relation to front center seat
# @PARAMS:
#   $fc -> Front Center seat #,#
#   $ss -> Selected seat for value #,#
# -
sub getSeatScore {
  my($fc,$ss) = @_;
  my($fcx,$fcy) = split(",",$fc);
  my($ssx,$ssy) = split(",",$ss);
  my($result) = abs($fcx - $ssx) + abs($fcy - $ssy);
  return $result;
}


# -
# Writes output to STDOUT
#   -> Supress output if global $DEBUG is false
# -
sub logger {
  if($DEBUG){
    print shift;
  }
}