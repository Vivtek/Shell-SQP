package Shell::SQP;

use 5.006;
use strict;
use warnings;

use DBI;
use base qw(Term::ShellUI);

use lib '.';


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
    my $firstarg = shift;
    unshift @_, $firstarg if defined $firstarg and $firstarg ne '-no-onstart';
    my %args = @_;
    my $self = $class->SUPER::new();
    bless($self, $class);
    
    $self->{appdir} = $args{appdir} || '.';
    $self->{dbname} = $args{dbname};
    
    # Define core commands
    $self->commands ($self->_core_commands());
    
    # Find the database for this app and connect to it
    $self->_find_databases();
    
    $self->{appdbh} = DBI->connect('dbi:SQLite:dbname=' . $self->{appdb});
    $self->{dbh} = DBI->connect('dbi:SQLite:dbname=' . $self->{db});
    $self->{sqp_settings} = $self->appget('select type from sqlite_master where name=?', 'sqp_settings') ? 1 : 0;
    
    # Add configured commands: (1) modules configured in sqp_settings, (2) scripts in directory, (3) modules in directory
    my $modules = $self->sqp_setting('modules');
    if ($modules) {
        foreach my $m (split /[ ,;]+/, $modules) {
            $self->_add_module ($m);
        }
    }
    $self->_find_scripts('app');
    $self->_find_scripts('local');
    $self->_add_modules ();
    
    my $prompt = $self->sqp_setting("prompt");
    unless ($prompt) {
        $prompt = $self->{db};
        $prompt =~ s/\.(.*?)$//;
    }
    $self->prompt($prompt . "> ");

    # Check settings for startup command(s).
    my $commands = $self->sqp_setting("start");
    if ($commands and (not defined $firstarg or $firstarg ne '-no-onstart')) {
       foreach my $c (split /;/, $commands) {
           $self->run($c);
       }
    }
    $self;
}

# Find the database in the app directory (if any) and in the local directory.

sub _find_databases {
    my ($self) = @_;
    
    if ($self->{appdir} ne '.') {
        opendir (D, $self->{appdir});
        my @dbs = sort grep {/.\sqlt$/} readdir (D);
        closedir (D);
        $self->{appdb} = $dbs[0] if @dbs;
        $self->{appdb} = 'sqp.sqlt';
        $self->{appdb} = $self->{appdir} . '/' . $self->{appdb};
    }
    
    if ($self->{dbname}) {
        $self->{db} = $self->{dbname};
    } else {
        opendir(D, '.');
        my @dbs = sort grep {/\.sqlt$/} readdir(D);
        closedir (D);

        if (@dbs) {
            $self->{db} = $dbs[0];
        } else {
            $self->{db} = 'sqp.sqlt';
        }
    }
    $self->{appdb} = $self->{db} unless $self->{appdb}
}

# Define commands for each script found in the directory.

sub _find_scripts {
    my $self = shift;
    my $where = shift;
    
    opendir(D, $where eq 'app' ? $self->{appdir} : '.');
    my @s = grep {/\.pl$/} readdir(D);
    closedir (D);
    
    my $cmds = {};
    foreach my $s (@s) {
        $s =~ s/\.pl$//;
        $self->_add_script_command ($s, $where);
    }
    $self->_mark_commands ($cmds, $where);
    return $cmds;
}

sub _add_script_command {
    my ($self, $command, $where) = @_;
    my $dir = '';
    $dir = $self->{appdir} . "\\" if $where eq 'app';
    $self->{csrc}->{$command} = "$dir$command.pl";
    my $cmds = {};
    $cmds->{$command} = {
        method => sub {
            my $cli = shift;
            my $parm = shift;
            my $c = "perl $dir$command.pl \"" . join ('" "', @{$parm->{args}}). '"';
            print "\n";
            system $c;
        }
    };
    $self->add_commands($cmds);
}

# Define commands for any modules in the directory that define commands.

sub _add_modules {
    my $self = shift;
    opendir(D, '.');
    my @s = grep {/\.pm$/} readdir(D);
    closedir (D);
    
    foreach my $m (@s) {
        $m =~ s/\.pm$//;
        $self->_add_module($m);
    }
}

sub _add_module {
    my $self = shift;
    my $module = shift;
    eval "require $module";
    if ($@) {
        print "$module: $@";
    } elsif ($module->can('sqp_commands')) {
        my $commands = $module->sqp_commands($self);
        $self->add_commands ($commands);
        $self->_mark_commands ($commands, "$module.pm");
    }
}

sub _mark_commands {
    my ($self, $commands, $mark) = @_;
    foreach my $command (keys %$commands) {
        $self->{csrc}->{$command} = $mark;
    }
}

=head2 query_yesno(prompt), ask(prompt)

For quick questions of the user on the command line, C<query_yesno> asks a yes/no question and looks for a 'y' or anything else as the first character in the
response, and C<ask> asks an arbitrary question and returns the entire response of the user.

=cut

sub query_yesno {
    my $self = shift;
    my $prompt = shift || "Are you sure? ";
    $self->{term}->readline($prompt) =~ /^y/i;
}

sub ask {
    my $self = shift;
    my $prompt = shift || "Information: ";
    my $default = shift;
    $self->{term}->readline($prompt) || $default;
}

=head2 prepare(sql)

A quick SQL statement prepare against the local database.

=cut

sub prepare {
    my $self = shift;
    my $statement = shift;
    $self->{dbh}->prepare($statement);
}

=head2 query(sql, args...)

Prepares an SQL statement against the local database, and executes it with the remaining arguments to the call.
Returns the statement handle.

=cut

sub query {
    my $self = shift;
    my $statement = shift;
    my $sth = $self->{dbh}->prepare($statement);
    $sth->execute(@_);
    return $sth;
}


=head2 get(sql, args...), appget(sql, args...)

Same as C<query> except it also does a fetchrow_arrayref on the resulting statement handle and returns the first row of results.
Obviously, this is best called if your query expects only a single row of results.

The C<appget> variant is just a C<get> against the app database instead of the local database.

=cut

sub get {
    my $self = shift;
    my $statement = shift;
    my $sth = $self->{dbh}->prepare($statement);
    $sth->execute(@_);
    my $row = $sth->fetchrow_arrayref;
    return unless $row;
    @$row;
}
sub appget {
    my $self = shift;
    my $statement = shift;
    my $sth = $self->{appdbh}->prepare($statement);
    $sth->execute(@_);
    my $row = $sth->fetchrow_arrayref;
    return unless $row;
    @$row;
}

=head2 sqp_setting (name)

Retrieves an SQP setting from the "sqp_settings" table in the app database, or from the local database if we're not
running as an app. If there is no sqp_settings table, returns a blank string.

=cut

sub sqp_setting {
    my $self = shift;
    return '' unless $self->{sqp_settings};
    my ($value) = $self->appget('select value from sqp_settings where name=?', shift || 'start');
    return $value;
}

=head2 change(sql, args...)

Prepares an updating SQL statement (not a SELECT) against the local database, executes it with the remaining arguments
to the call, and returns the result from last_insert_id against the database handle.

=cut

sub change {
    my $self = shift;
    my $statement = shift;
    my $sth = $self->{dbh}->prepare($statement);
    $sth->execute(@_) or return;
    my $insert = $self->{dbh}->last_insert_id("","","","");
    $insert;
}

# Now let's define all the core commands to be provided.

sub _core_commands {
 my $self = shift;

 my $commands = {
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
     "command" => {
         method => \&_command
     },
     "directory" => {
         method => \&_directory
     },
     "dos" => {
         method => \&_dos
     },
     "sql"    => {
         method => sub { system "sqlite3 " . shift->{db}; }
     },
     "quit" => {
         method => sub { shift->exit_requested(1); }
     },
     "exit" => {
         method => sub { shift->exit_requested(1); }
     },
 };
 $self->_mark_commands ($commands, 'core');
 return $commands;
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

sub _directory {
    system "start explorer .";
}
sub _dos {
    system "start cmd.exe";
}

sub _command {
    my $self = shift;
    @_ = @{shift->{tokens}}; shift;

    my $command = shift || return;
    
    if (not defined $self->{csrc}->{$command}) {
        if ($self->query_yesno("$command is not defined.  Define it? [y]")) {
            $self->_start_script($command);
        }
        return;
    }
    
    if ($self->{csrc}->{$command} eq 'core') {
        if ($self->query_yesno("$command is is a core command.  Override it with a new local script? [y]")) {
            $self->_start_script($command);
        }
        return;
    }
    if ($self->{csrc}->{$command} eq 'app') {
        if ($self->query_yesno("$command is is an app command.  Override it with a new local script? [y]")) {
            $self->_start_script($command);
        }
        return;
    }
    if ($self->{csrc}->{$command} =~ /\.pl$/) {
        print "$command is a local Perl script.\n";
        system "start $command.pl" if -e "$command.pl";
        return;
    }
    if ($self->{csrc}->{$command} =~ /\.pm$/) {
        print "$command is defined in a local module.\n";
        system "start " . $self->{csrc}->{$command};
        return;
    }
}

sub _start_script {
    my ($self, $command) = @_;
    open C, ">$command.pl";
    print C "use Shell::SQP;\n";
    print C "use strict;\n";
    print C "use warnings;\n";
    print C "my \$ctx = Shell::SQP->new('-no-onstart'";
    if ($self->{appdir} ne '.') {
        print C ", 'appdir', '" . $self->{appdir} . "'";
    }
    if ($self->{dbname}) {
        print C ", 'dbname', '" . $self->{dbname} . "'";
    }
    print C ");\n";
    print C "\n";
    close C;
    system "start $command.pl";
            
    $self->_add_script_command ($command);
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
