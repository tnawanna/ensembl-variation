# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#      http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Script to generate an HTML page containing the variation sources of each species


=head1 CONTACT

  Please email comments or questions to the public Ensembl
  developers list at <http://lists.ensembl.org/mailman/listinfo/dev>.

  Questions may also be sent to the Ensembl help desk at
  <helpdesk.org>.

=cut


use Bio::EnsEMBL::Registry;
use DBI;
use strict;
use POSIX;
use Getopt::Long;

###############
### Options ###
###############
my ($e_version,$html_file,$hlist,$phost,$user,$port,$help);
## EG options
my ($site, $etype);

usage() if (!scalar(@ARGV));
 
GetOptions(
     'v=s'     => \$e_version,
     'o=s'     => \$html_file,
     'help!'   => \$help,
     'hlist=s' => \$hlist,
     'phost=s' => \$phost,
     'user=s'  => \$user,
     'port=i'  => \$port,
     'site=s'  => \$site,
     'etype=s' => \$etype
);

if (!$e_version) {
  print "> Error! Please give an Ensembl version, using the option '-v' \n";
  usage();
}
if (!$html_file) {
  print "> Error! Please give an output file using the option '-o'\n";
  usage();
}
if (!$hlist) {
  print "> Error! Please give the list of host names where the new databases are stored using the option '-hlist'\n";
  usage();
}
if (!$user) {
  print "> Error! Please give user name using the option '-user'\n";
  usage();
}

usage() if ($help);

my $server_name = 'http://static.ensembl.org';
my $ecaption = 'Ensembl';
my @hostnames = split /,/, $hlist;

if ($site) {
  $server_name = $site;
}

# Settings
my $database = "";
my $pswd = "";
my $db_type = 'variation';
my $default_port = 3306;
$port ||= $default_port;
my $p_version = $e_version-1;

my $html;

##############
### Header ###
##############
my $html_header = q{
<html>
<head>
  <title>Detailed species data count</title>
  <script type="text/javascript">
    window.onload = function() {
      $('.ht').helptip({'track': true});
    };
  </script>
</head>

<body>

<div>
};

#############
### Title ###
#############
my $html_title = qq{
  <div style="float:left;width:80%">
    <h1 style="margin-top:15px">Ensembl Variation - Detailed species data count</h1>

    <h2>List of data counts by category and species - $ecaption $e_version</h2>

    <div>
      <a href="sources_documentation.html">See documentation for all the variant sources &rarr;</a>
    </div>
    
    <h2 id="phenotype" style="margin-top:25px">Phenotype/disease/trait data</h2>
    <div>
      <span>The list of phenotype/disease/trait association sources by species is available in the page <a href="sources_phenotype_documentation.html">Phenotype sources</a>.</span>
    </div>
};

##############
### Legend ###
##############
my $html_legend = qq{
  <!-- Right hand side legend -->
  <div style="float:right;width:200px;top:20px">
    <div style="margin: 2px 0px 16px 8px;padding-bottom:2px;background-color:#F9F9F9;color:#333;border-left:1px dotted #22949b;border-right:1px dotted #22949b;border-bottom:1px dotted #22949b">
      <div style="padding:5px;font-weight:bold;color:#000;background-color:#FFF;border-top:2px solid #22949b;border-bottom:1px solid #22949b;margin-bottom:5px">
        <img src="/i/16/info.png" style="vertical-align:top" alt="info" /> 
        Colour legend
    </div>
    <table>
};

##############
### Footer ###
##############
my $html_footer = q{
  </div>
</div>
</body>
</html>};

   
my %colours = ( 'lot_million' => { 'order' => 1, 'colour' => '#800',    'legend' => 'From 10 million'},
                'few_million' => { 'order' => 2, 'colour' => '#007',    'legend' => 'From 1 million to 9.9 million'},
                'thousand'    => { 'order' => 3, 'colour' => '#006266', 'legend' => 'From 1,000 to 999,999'},
                'hundred'     => { 'order' => 4, 'colour' => '#070',    'legend' => 'From 1 to 999'},
                'zero'        => { 'order' => 5, 'colour' => '#CCC',    'legend' => 'No data'}
              );  

my $sql = qq{SHOW DATABASES LIKE '%$db_type\_$e_version%'};

my %sql_list = ( "Structural variant" => { 'sqla'  => { 'sql'   => q{SELECT COUNT(sv.structural_variation_id) FROM structural_variation sv, source s 
                                                                     WHERE sv.is_evidence=0 AND s.source_id=sv.source_id AND s.name="DGVa"},
                                                        'label' => 'Structural variant'
                                                      }, 
                                           'sqlb'  => { 'sql'   => q{SELECT COUNT(sv.structural_variation_id) FROM structural_variation sv, source s 
                                                                    WHERE sv.is_evidence=1 AND s.source_id=sv.source_id AND s.name="DGVa"},
                                                        'label' => 'Supporting evidence'
                                                      }, 
                                         },
                   "Citation"         => { 'sqla'  => { 'sql'   => q{SELECT COUNT(DISTINCT variation_id) FROM variation_citation},
                                                        'label' => 'Cited sequence variant'
                                                      }, 
                                            'sqlb'  => { 'sql'   => q{SELECT COUNT(DISTINCT publication_id) FROM variation_citation},
                                                         'label' => 'Publication'
                                                      },
                                         },
                   "Phenotype"        => { 'sqla'  => { 'sql'   => q{SELECT COUNT(phenotype_id) FROM phenotype},
                                                        'label' => 'Phenotype'
                                                      },
                                           'sqlb'  => { 'sql'   => q{SELECT COUNT(phenotype_feature_id) FROM phenotype_feature},
                                                        'label' => 'Phenotype association'
                                                      },
                                           'extra' => q{The list of phenotype/disease/trait association sources by species is available in the page <a href="sources_phenotype_documentation.html">Phenotype sources</a>.}
                                         },
                   "Genotype"         => { 'sqla'  => { 'sql'   => q{SELECT COUNT(sample_id) FROM sample WHERE description NOT LIKE "%DGVa%"},
                                                        'label' => 'Sample'
                                                      },
                                           'sqlb'  => { 'sql'   => q{SELECT COUNT(population_id) FROM population WHERE name NOT LIKE "COSMIC%"},
                                                        'label' => 'Population'
                                                      }
                                         },
                   "Prediction"       => { 'sqla'  => { 'sql'   => q{SELECT COUNT(distinct vf.variation_id) FROM variation_feature vf, transcript_variation tv, meta m 
                                                                     WHERE vf.variation_feature_id=tv.variation_feature_id AND m.meta_key="sift_version" 
                                                                     AND tv.sift_score IS NOT NULL},
                                                        'label' => 'Variants with SIFT data'
                                                      },
                                           'sqlb' =>  { 'sql'   => q{SELECT COUNT(distinct vf.variation_id) FROM variation_feature vf, transcript_variation tv, meta m
                                                                     WHERE vf.variation_feature_id=tv.variation_feature_id AND m.meta_key="polyphen_version" 
                                                                     AND tv.polyphen_score IS NOT NULL},
                                                        'label' => 'Variants with PolyPhen data'
                                                      }
                                         } # Too long ?
               );
my @sql_order = ("Structural variant","Genotype","Phenotype","Citation","Prediction");                       
                                           
my $sql_core = qq{SELECT meta_value FROM meta WHERE meta_key="species.display_name" LIMIT 1};

# Get the populated tables by species
my $bg = '';
my $th_bg = qq{background-color:#BBB};
my $th_border_left = qq{border-left:1px solid #DDD};
my $th_border_left_top = qq{style="$th_border_left;text-align:center"};

foreach my $type (@sql_order) {

  if (!$sql_list{$type}) {
    print STDERR "Can't recognise the category '$type'! Skip this category.\n";
    next;
  }

  print "\n# $type\n";
  my $lc_type = lc($type);
  
  my %species_list;
  my %display_list;
  
  my $sql_a   = $sql_list{$type}{'sqla'}{'sql'};
  my $label_a = $sql_list{$type}{'sqla'}{'label'};
  
  my $sql_b   = $sql_list{$type}{'sqlb'}{'sql'};
  my $label_b = $sql_list{$type}{'sqlb'}{'label'};
  my $b_type;

  foreach my $hostname (@hostnames) {
    
    my $sth = get_connection_and_query($database, $hostname, $sql);

    # loop over databases
    while (my ($dbname) = $sth->fetchrow_array) {
      next if ($dbname =~ /^master_schema/);
      next if ($dbname =~ /sample$/);
      
      print $dbname;
      $dbname =~ /^(.+)_variation/;
      my $s_name = $1;
      
      if ($etype) { # EG site - need to filter out species
        my $img_thumb = sprintf qq{eg-plugins/%s/htdocs/img/species/thumb_%s.png}, $etype, ucfirst($s_name);
        #  print "- checking for $img_thumb ... ";
        if (! -e $img_thumb) {
          print "\t... skipping \n";
          next;
        } 
      }
      print "\n";
      
      my $label_name = ucfirst($s_name);
         $label_name =~ s/_/ /g;
      $species_list{$s_name}{label} = $label_name;
      
      # Get species display name
      my $core_dbname = $dbname;
         $core_dbname =~ s/variation/core/i;
      my $sth_core = get_connection_and_query($core_dbname, $hostname, $sql_core);
      my $display_name = $sth_core->fetchrow_array;  
         $display_name =~ s/saccharomyces/S\./i;
      $species_list{$s_name}{'name'} = $display_name;
      $display_list{$display_name} = $s_name;
      
      # Count the number of variations
      my $sth_a = get_connection_and_query($dbname, $hostname, $sql_a);
      my $res_a = $sth_a->fetchrow_array;
      $sth_a->finish;
      $species_list{$s_name}{'a'} = $res_a;

      # Count the number of variations
      my $sth_b = get_connection_and_query($dbname, $hostname, $sql_b);
      my $res_b = $sth_b->fetchrow_array;
      $sth_b->finish;
      $species_list{$s_name}{'b'} = $res_b;

      # Previous database
      my $sql3 = qq{SHOW DATABASES LIKE '%$s_name\_variation_$p_version%'};
      my $sth3 = get_connection_and_query($database, $phost, $sql3);
      my $p_dbname = $sth3->fetchrow_array;

      if ($p_dbname) {
        # Previous variants
        my $sth4a = get_connection_and_query($p_dbname, $phost, $sql_a);
        my $p_res_a = $sth4a->fetchrow_array;
        $sth4a->finish;
        $species_list{$s_name}{'p_a'} = $res_a-$p_res_a;
        # Previous publications
        my $p_res_b;
        if ($res_b =~ /^\d+$/) {
          $b_type = "num";
          my $sth4b = get_connection_and_query($p_dbname, $phost, $sql_b);
          $p_res_b = $sth4b->fetchrow_array;
          $sth4b->finish;
          $species_list{$s_name}{'p_b'} = $res_b-$p_res_b;
        }
      }
    }
  }

  
  my $html_content = qq{
    <table class="ss" style="width:auto">
      
      <tr class="ss_header">
        <th style="$th_bg">Species</th>  
        <th style="$th_bg;$th_border_left">$label_a</th>
        <th style="$th_bg;padding-left:0px">
          <span class="_ht ht" title="$label_a count difference with the previous Ensembl release (v.$p_version)">
            <small>(e!$p_version &rarr; e!$e_version)</small>
          </span>
        </th>
        <th style="$th_bg;$th_border_left">$label_b</th>
     };
  if ($b_type eq 'num') {
       $html_content .= qq{   
        <th style="$th_bg;padding-left:0px">
          <span class="_ht ht" title="$label_b count difference with the previous Ensembl release (v.$p_version)">
            <small>(e!$p_version &rarr; e!$e_version)</small>
          </span>
        </th>\n};
  }
  $html_content .= qq{      </tr>};
  
  # Loop to display the data by species
  $bg = '';
  my $count_species = 0;
  foreach my $display_name (sort keys(%display_list)) {

    my $sp = $display_list{$display_name};
    my $label = $species_list{$sp}{'label'};
    my $uc_sp = ucfirst($sp);      
    my $img_src = "/i/species/48/$uc_sp.png";
    my $display_name = $species_list{$sp}{'name'};
    my $a_count = $species_list{$sp}{'a'};
    my $b_count = $species_list{$sp}{'b'};
    
    next if ($a_count eq "0" && ($b_count eq "0" && $b_type eq 'num'));
    next if ($a_count eq "0" && $b_type ne 'num');
    
    $count_species++;
    $a_count = round_count($a_count,$lc_type);
    $b_count = ($b_type eq 'num') ? round_count($b_count,$lc_type) : qq{<ul style="margin-bottom:0px"><li style="margin-top:0px">}.join("</li><li>", split(',',$b_count))."</li></ul>";
    my $a_p_count = round_count_diff($species_list{$sp}{'p_a'},$lc_type);
    my $b_p_count = ($b_type eq 'num') ? round_count_diff($species_list{$sp}{'p_b'},$lc_type) : undef;
  
    my $b_align = ($b_type eq 'num') ? 'right' : 'left';
    if ($b_type ne 'num') {
      $b_count =~ s/StructuralVariation/Structural Variation/;
      $b_count =~ s/SupportingStructuralVariation/Supporting Structural Variation/;
    }
    
    # Species data
    $html_content .= qq{
    <tr$bg style="vertical-align:middle">
      <td>
        <div>
          <div style="float:left">
            <a href="/$uc_sp/Info/Index" title="$label Ensembl Home page" style="vertical-align:middle" target="_blank">
              <img src="$img_src" alt="$label" class="sp-thumb" style="vertical-align:middle;width:28px;height:28px" />
            </a>
           </div>
           <div style="float:left;margin-left:4px">
             <div class="bigtext">$display_name</div>
             <div class="small" style="font-style:italic">$label</div>
           </div>
           <div style="clear:both"></div>
         </div>
      </td>
      <td style="text-align:right">$a_count</td>
      <td style="text-align:right">$a_p_count</td>
      <td style="text-align:$b_align">$b_count</td>\n};
    $html_content .= qq{      <td style="text-align:right">$b_p_count</td>\n} if ($b_type eq 'num');
    $html_content .= qq{  </tr>};
    $bg = set_bg();
  }
  $html_content .= qq{</table>\n};

  my $h2_style = 'style="margin-top:40px"';
  $html .= qq{<h2 id="$lc_type"$h2_style>$type data</h2>};
  $html .= q{<p>}.$sql_list{$type}{'extra'}.q{</p>} if ($sql_list{$type}{'extra'});
  $html .= qq{<p style="padding-top:0px;margin-top:0px">There are currently <span style="font-weight:bold;font-size:1.1em;color:#000">$count_species</span> species with $lc_type data in the variation databases in Ensembl:</p>\n};
  $html .= $html_content;
  #$html .= $html_legend;
}


# Legend
foreach my $type (sort { $colours{$a}{'order'} <=> $colours{$b}{'order'} } keys(%colours)) {
  my $desc   = $colours{$type}{'legend'};
  my $colour = $colours{$type}{'colour'};

  $html_legend .= qq{
      <tr>
        <td style="padding-top:4px;text-align:center">
          <span style="background-color:$colour;color:#FFF;border-radius:5px;padding:1px 2px 1px 20px;cursor:default"></span>
        </td>
        <td style="padding-top:4px">$desc</td>
      </tr>};
}
$html_legend .= qq{    </table>\n  </div>\n</div>};

  

######################
## HTML/output file ##
######################
open  HTML, "> $html_file" or die "Can't open $html_file : $!";
print HTML $html_header."\n";
print HTML $html_legend."\n";
print HTML $html_title."\n";
print HTML $html."\n";
print HTML qq{<p style="padding-top:15px">The <b>full list of species</b> with their assembly versions in Ensembl is available <a href="/info/about/species.html">here</a>.</p>\n};
print HTML $html_footer."\n";
close(HTML);



###############
### Methods ###
###############

# Connects and execute a query
sub get_connection_and_query {
  my $dbname = shift;
  my $hname  = shift;
  my $sql    = shift;
  
  my ($host, $port) = split /\:/, $hname;
  
  # DBI connection 
  my $dsn = "DBI:mysql:$dbname:$host:$port";
  my $dbh = DBI->connect($dsn, $user, $pswd) or die "Connection failed";

  my $sth = $dbh->prepare($sql);
  $sth->execute;
  return $sth;
}


sub round_count {
  my $count = shift;
  my $type = shift;
     $type ||= 'variants';
  my $symbol = '+';
  
  my $count_label;
  my $count_display;
  my $bg_color;
  # From 1 to 9.9 million
  if ($count =~ /^(\d)(\d)\d{5}$/) {
    my $number = ($2!=0) ? "$1.$2" : $1;
    $count = "$number million";
    $count_label = "Over $count $type";
    $count_display = "$count$symbol";
    $bg_color = $colours{'few_million'}{'colour'};
  }
  # From 10 million
  elsif ($count =~ /^(\d+)\d{6}$/) {
    my $number = $1;
    $count = "$number million";
    $count_label = "Over $count $type";
    $count_display = "$count$symbol";
    $bg_color = $colours{'lot_million'}{'colour'};
  }
  # From 1,000 to 999,999
  elsif ($count =~ /^(\d+)\d{3}$/) {
    $count = "$1,000";
    $count_label = "Over $count $type";
    $count_display = "$count$symbol";
    $bg_color = $colours{'thousand'}{'colour'};
  }
  # From 1 to 999
  elsif ($count > 0) {
    $count_label = "$count $type";
    $count_display = "$count";
    $bg_color = $colours{'hundred'}{'colour'};
  }
  # No data
  else {
    $count_label = "No data";
    $count_display = "$count";
    $bg_color = $colours{'zero'}{'colour'};
  }
  return qq{<span style="background-color:$bg_color;color:#FFF;border-radius:5px;padding:3px 3px 1px;cursor:help;white-space:nowrap" title="$count_label">$count_display</span>};
}

sub round_count_diff {
  my $count = shift;
  my $type = 'variants';

  my ($count_label,$colour,$symbol,$label);

  if ($count == 0) {
    return '-';
  }
  elsif ($count > 0) {
    $colour = '#090';
    $symbol = '+';
    $label  = 'more'
  }
  else {
    $colour = '#900';
    $symbol = '-';
    $label  = 'less';
  }
  $count = abs($count);

  # From 1 to 9.9 million
  if ($count =~ /^(\d)(\d)\d{5}$/) {
    my $number = ($2!=0) ? "$1.$2" : $1;
    $count = "$number million";
    $count_label = "Over $count $label $type";
  }
  # From 10 million
  elsif ($count =~ /^(\d+)\d{6}$/) {
    my $number = $1;
    $count = "$number million";
    $count_label = "Over $count $label $type";
  }
  # From 1,000 to 999,999
  elsif ($count =~ /^(\d+)\d{3}$/) {
    $count = "$1,000";
    $count_label = "Over $count $label $type";
  }
  # From 1 to 999
  else {
    $count =~ /(\d+)$/;
    $count = $1;
    $count_label = "$count $label $type";
  }
  return qq{<span style="color:$colour" title="$count_label"><small>($symbol$count)</small></span>};
}


sub set_bg {
  return ($bg eq '') ? ' class="bg2"' : '';
}

sub usage {
  
  print qq{
  Usage: perl species_list_detailed_counts.pl [OPTION]
  
  Put detailed data information for each species, into an HTML document.
  
  Options:

    -help           Print this message
      
    -v              Ensembl version, e.g. 65 (Required)
    -o              An HTML output file name (Required)      
    -hlist          The list of host names where the new databases are stored, separated by a coma,
                    e.g. ensembldb.ensembl.org1, ensembldb.ensembl.org2 (Required)
    -phost          Host name where the previous databases are stored, e.g. ensembldb.ensembl.org  (Required)
    -user           MySQL user name (Required)
    -port           MySQL port. 3306 by default (optional)
    -site           The URL of the website (optional)
    -etype          The type of Ensembl, e.g. Plant (optional)
  } . "\n";
  exit(0);
}