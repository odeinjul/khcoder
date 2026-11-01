# Smoke test for the Windows bundle. Run from the bundle root with the bundled perl:
#   perl smoke_test.pl
# Starts KH Coder exactly as kh_coder.pl does (MariaDB, R, Tk GUI), then creates one
# project per language, runs pre-processing, checks the extracted words, draws an R plot
# through KH Coder's R bridge, writes smoke_results.txt and exits (0 = pass).
use strict;
use utf8;
use Encode ();
use POSIX ();

my @cases = (
	# lang, method,     sample file,                  base form expected in the word list
	[ 'en', 'stanford', 'smoke_samples/en.txt', 'run'  ],
	[ 'jp', 'mecab',    'smoke_samples/jp.txt', '猫'   ],
	[ 'cn', 'stanford', 'smoke_samples/cn.txt', '经济' ],
);

open(my $res, '>:encoding(UTF-8)', 'smoke_results.txt') or die "smoke_results.txt: $!";
$res->autoflush(1);
my $failures = 0;

sub report {
	my $line = shift;
	print $res "$line\n";
	print "SMOKE: ", Encode::encode('UTF-8', $line), "\n";
}

BEGIN {
	require Tk;
	no warnings 'redefine';

	# Run the tests once KH Coder's main window is up.
	my $main_loop = \&Tk::MainLoop;
	*Tk::MainLoop = sub {
		$::main_gui->mw->after(2000, \&run_tests);
		$main_loop->();
	};

	# Answer dialogs instead of waiting for a click, and log what they said.
	*Tk::messageBox = sub {
		my ($widget, %a) = @_;
		my $type = lc($a{-type} // 'ok');
		my $icon = lc($a{-icon} // '');
		my $answer = $type =~ /^ok/ ? 'Ok' : $type =~ /^yes/ ? 'Yes' : $type =~ /retry/ ? 'Cancel' : 'Ok';
		my $msg = $a{-message} // '';
		$msg = Encode::decode('UTF-8', $msg) unless utf8::is_utf8($msg);
		report("dialog [$icon/$type -> $answer]: $msg");
		$failures++ if $icon eq 'error';
		return $answer;
	};
}

sub run_tests {
	my $ok = eval {
		test_language(@$_) for @cases;
		1;
	};
	unless ($ok) {
		report("FAIL: $@");
		$failures++;
	}
	report($failures ? "RESULT: FAIL ($failures)" : 'RESULT: PASS');
	close $res;
	POSIX::_exit($failures ? 1 : 0);
}

sub test_language {
	my ($lang, $method, $file, $expect) = @_;
	my $path = $::config_obj->cwd . "/$file";

	gui_window::project_new->open;
	my $win = $::main_gui->get('w_new_pro');
	$win->{e1}->insert(0, gui_window->gui_jchar($path));
	$win->{e2}->insert(0, "smoke test $lang");
	$win->{lang_menu}->set_value($lang);
	$win->refresh_method;
	$win->{method} = $method;
	$win->_make_new or die "$lang: could not create project\n";   # also runs pre-processing

	my $words = mysql_words->num_all;
	report("$lang/$method: $words words");
	die "$lang: no words extracted\n" unless $words > 0;

	my $hit = mysql_exec->select("SELECT COUNT(*) FROM genkei WHERE name = '$expect'", 1)
		->hundle->fetch->[0];
	report("$lang: base form '$expect' " . ($hit ? 'found' : 'MISSING'));
	$failures++ unless $hit;

	my $plot = kh_r_plot->new(
		name      => "smoke_$lang",
		command_f => "library(maptools)\nlibrary(ggplot2)\n"
		           . "x <- 1:10\ny <- rev(x)\nplot(x, y)\n"
		           . "pointLabel(x, y, labels = paste0('w', x))\n",
		width     => 480,
		height    => 480,
	);
	my @files = $plot ? grep { -s $_ } glob("$plot->{path}*") : ();
	report("$lang: R plot " . (@files ? "ok (@files)" : 'FAILED'));
	$failures++ unless @files;

	$::main_gui->{menu}->mc_close_project;
}

do './kh_coder.pl';
die $@ if $@;
