package Shell::SQP;

use 5.006;
use strict;
use warnings;

use DBI;
use base qw(Term::ShellUI);

=head1 NAME

Shell::SQP - Represents a CLI session

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';


=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use Shell::SQP;

    my $foo = Shell::SQP->new();
    ...

=head1 METHODS

=head2 new

Creates a new shell object; finds and opens the database, scans for modules and scripts defining commands, etc.

=cut

sub new {
    my $class = shift;
    my $self = $class->SUPER::new(@_);
    bless($self, $class);
    $self->commands (_core_commands());
    $self->add_commands (_find_scripts());
    my $prompt = _find_database();
    $self->{db} = $prompt;
    $prompt =~ s/\.sqlt$//;
    $self->prompt($prompt . "> ");
    $self->{dbh} = DBI->connect('dbi:SQLite:dbname=' . $self->{db});
    $self;
}

# Find a database in the current directory.

sub _find_database {
    opendir(D, '.');
    my @dbs = sort grep {/\.sqlt$/} readdir(D);
    closedir (D);
    
    return $dbs[0] if @dbs;
    return 'sqp.sqlt';
}

# Define commands for each script found in the directory.

sub _find_scripts {
    opendir(D, '.');
    my @s = grep {/\.pl$/} readdir(D);
    closedir (D);
    
    my $cmds = {};
    foreach my $s (@s) {
        my $command = $s;
        $command =~ s/\.pl$//;
        $cmds->{$command} = {
            method => sub {
                my $cli = shift;
                my $parms = shift;
                my $c = "perl $s " . join (' ', @{$parms->{args}});
                print "\n";
                system $c;
            }
        }
    }
    return $cmds;
}

# Get a yes/no answer from the user

sub query_yesno {
    my $self = shift;
    my $prompt = shift || "Are you sure? ";
    $self->{term}->readline($prompt) =~ /^y/i;
}

# Now let's define all the core commands to be provided.

sub _core_commands {
 return ({
     "select" => {
         method => \&_select
     },
     "update" => {
         method => \&_update
     },
     "delete" => {
         method => \&_delete
     },
     "insert" => {
         method => \&_insert
     },
     "backup" => {
         method => \&_backup
     },
     "quit" => {
         method => sub { shift->exit_requested(1); }
     },
 });
}

sub _select {
    my $self = shift;
    my $parms = shift;
    my $select = $parms->{rawline};
    my $sth = $self->{dbh}->prepare($select) or return;
    $sth->execute;
    while (my $row = $sth->fetchrow_arrayref) {
        print join '|', map { defined $_ ? $_ : ''} @$row;
        print "\n";
    }
}

sub _delete {
    my $self = shift;
    my $parms = shift;
    my $delete = $parms->{rawline};
    if ($delete =~ / where / || $self->query_yesno("Really delete everything? ")) {
        my $sth = $self->{dbh}->prepare($delete) or return;
        $sth->execute;
    }
}

sub _insert {
    my $self = shift;
    my $parms = shift;
    my $insert = $parms->{rawline};
    my $sth = $self->{dbh}->prepare($insert) or return;
    $sth->execute;
}

sub _update {
    my $self = shift;
    my $parms = shift;
    my $update = $parms->{rawline};
    if ($update =~ / where / || $self->query_yesno("Really update everything? ")) {
        my $sth = $self->{dbh}->prepare($update) or return;
        $sth->execute;
    }
}

sub _backup {
    my $self = shift;
    print "backing up\n";
}



=head1 AUTHOR

Michael Roberts, C<< <michael at vivtek.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-shell-sqp at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Shell-SQP>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Shell::SQP


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Shell-SQP>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Shell-SQP>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Shell-SQP>

=item * Search CPAN

L<http://search.cpan.org/dist/Shell-SQP/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2012 Michael Roberts.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1; # End of Shell::SQP
