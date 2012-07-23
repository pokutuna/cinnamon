package Cinnamon::Local;
use strict;
use warnings;
use Carp ();
use IPC::Run ();
use Cinnamon::Logger;

sub host {
    return undef;
}

sub execute {
    my ($class, @cmd) = @_;
    my $result = IPC::Run::run \@cmd, \my $stdin, \my $stdout, \my $stderr;
    chomp for ($stdout, $stderr);

    for my $line (split "\n", $stdout) {
        log info => sprintf "[localhost :: stdout] %s",
            $line;
    }
    for my $line (split "\n", $stderr) {
        log info => sprintf "[localhost :: stdout] %s",
            $line;
    }

    +{
        stdout    => $stdout,
        stderr    => $stderr,
        has_error => !$result,
        error     => $?,
    };
}

!!1;
