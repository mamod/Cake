use 5.010001;
use ExtUtils::MakeMaker;

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'Cake',
    VERSION_FROM      => 'lib/Cake.pm', # finds $VERSION
    #EXE_FILES    => ['script/cake'],
    PREREQ_PM         => {
	#'YAML::Tiny' => 0
    },
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/Cake.pm', # retrieve abstract from module
       AUTHOR         => 'Mamod A. Mehyar <mamod.mehyar@gmail.com>') : ())
);
