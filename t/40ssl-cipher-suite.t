use strict;
use warnings;
use File::Temp qw(tempfile);
use Net::EmptyPort qw(check_port empty_port);
use Scope::Guard qw(scope_guard);
use Test::More;
use t::Util;

my $port = empty_port();

# spawn server that only accepts AES128-SHA
my ($conffh, $conffn) = tempfile(UNLINK => 1);
print $conffh <<"EOT";
listen:
  host: 127.0.0.1
  port: $port
  ssl:
    key-file: examples/h2o/server.key
    certificate-file: examples/h2o/server.crt
    cipher-suite: AES128-SHA
    cipher-suite-tls1.3: TLS_CHACHA20_POLY1305_SHA256
    max-version: TLSv1.3
hosts:
  default:
    paths:
      /:
        file.dir: @{[ DOC_ROOT ]}
EOT
my ($guard, $pid) = spawn_server(
    argv     => [ bindir() . "/h2o", "-c", $conffn ],
    is_ready => sub {
        check_port($port);
    },
);

subtest "tls1.2" => sub {
    # connect to the server with AES256-SHA as the first choice, and check that AES128-SHA was selected
    my $log = `openssl s_client -tls1_2 -cipher AES256-SHA:AES128-SHA -host 127.0.0.1 -port $port < /dev/null 2>&1`;
    like $log, qr/^\s*Cipher\s*:\s*AES128-SHA\s*$/m;

    # connect to the server with AES256-SHA as the only choice, and check that handshake failure is returned
    $log = `openssl s_client -tls1_2 -cipher AES256-SHA -host 127.0.0.1 -port $port < /dev/null 2>&1`;
    like $log, qr/alert handshake failure/m; # "handshake failure" the official name for TLS alert 40
};

subtest "tls1.3" => sub {
    # TLS 1.3 test
    my $log = `openssl s_client -tls1_3 -ciphersuites TLS_AES_128_GCM_SHA256:TLS_CHACHA20_POLY1305_SHA256 -host 127.0.0.1 -port $port < /dev/null 2>&1`;
    like $log, qr/^\s*Cipher\s*:\s*TLS_CHACHA20_POLY1305_SHA256\s*$/m;

    $log = `openssl s_client -tls1_3 -ciphersuites TLS_AES_256_GCM_SHA384 -host 127.0.0.1 -port $port < /dev/null 2>&1`;
    unlike $log, qr/TLS_AES_256_GCM_SHA384/m;
};

done_testing;
