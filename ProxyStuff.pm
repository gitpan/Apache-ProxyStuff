package Apache::ProxyStuff;

use strict;
use vars qw(@ISA $VERSION);
use Apache::Constants qw(:common);
use Apache::Log;
use Apache::Table;
use HTML::TokeParser;
use LWP::UserAgent;
use Data::Dumper;

@ISA = qw(LWP::UserAgent);
$VERSION = '0.05';

my $UA = __PACKAGE__->new;
$UA->agent(join "/", __PACKAGE__, $VERSION);

# Override Methods
sub redirect_ok {return 0}

# Helper Subs
sub open_body {
  my ($token, $r, $header, $body_attributes) = @_;
  
  # Print body tag
  print q(<BODY);
  
  # Replace existing body attributes with new ones if necessary
  if ($body_attributes) {
	foreach my $pair (split /\s+/, $body_attributes) {
	  my ($attr, $value) = split /=/, $pair;
	  $token->[2]->{lc $attr} = $value; # Keys are lowercase
	} # End foreach
  } # End if

  # Print attributes
  my $atts = join(' ', map({"$_=$token->[2]->{$_}"} keys %{$token->[2]}));
  print qq( $atts) if $atts;
  
  # Close body tag
  print qq(>);

  # Send the header
  print $header;
} # End open_body()

sub close_body {
  my ($token, $r, $footer) = @_;
    
  # Send the footer
  print $footer;
  print $token->[-1];
} # End close_body()

sub a_href {
  my ($token, $r, $add_host2href) = @_;

  # Open tag
  print qq(<A);

  # Modify href
  if ($token->[2]->{'href'} =~ /^\//) { # Modify if absolute URI
	$token->[2]->{'href'} = qq(/$add_host2href) . $token->[2]->{'href'};
  } # End unless
    
  # Print attributes
  my $atts = join(' ', map({"$_=$token->[2]->{$_}"} keys %{$token->[2]}));
  print qq( $atts) if $atts;
    
  # Close tag
  print qq(>);
} # End a_href()

sub img_src {
  my ($token, $r, $add_host2img_src) = @_;
  
  # Open tag
  print qq(<IMG);
    
  # Modify src
  if ($token->[2]->{'src'} =~ /^\//) { # Modify is absolute URI
	$token->[2]->{'src'} = qq(/$add_host2img_src) . $token->[2]->{'src'};
  } # End unless
  
  # Print attributes
  my $atts = join(' ', map({"$_=$token->[2]->{$_}"} keys %{$token->[2]}));
  print qq( $atts) if $atts;
    
  # Close tag
  print qq(>);
} # End a_href()

sub form_action {
  my ($token, $r, $add_host2form_action) = @_;

  # Open tag
  print qq(<FORM);
    
  # Modify action
  if ($token->[2]->{'action'} =~ /^\//) { # Modify is absolute URI
      $token->[2]->{'action'} = qq(/$add_host2form_action) . $token->[2]->{'action'};
  } # End unless
    
  # Print attributes
  my $atts = join(' ', map({"$_=$token->[2]->{$_}"} keys %{$token->[2]}));
  print qq( $atts) if $atts;
    
  # Close tag
  print qq(>);
} # End a_href()

sub process_text {
  
  my ($content, $r, $header, $footer, $body_attributes, $add_host2href, $add_host2img_src, 
	  $add_host2form_action) = @_;

  # Parse the document
  my $parser = new HTML::TokeParser($content);
  my ($saw_header, $saw_footer); # We need these for broken docs that have multiple <BODY></BODY> tags
  while (my $token = $parser->get_token) {

      # Handle <body>
      if ($token->[0] eq 'S' and $token->[1] eq 'body' and not $saw_header) {
		open_body($token, $r, $header, $body_attributes);
		$saw_header++;
	  } # End if
      
      # Handle </body>
      elsif ($token->[0] eq 'E' and $token->[1] eq 'body' and not $saw_footer) {
		close_body($token, $r, $footer);
		$saw_footer++;
	  } # End elsif
      
      # Handle <A HREF>
      elsif ($add_host2href and $token->[0] eq 'S' and $token->[1] eq 'a' and
	     $token->[2]->{'href'}) {a_href($token, $r, $add_host2href)}

      # Handle <IMG SRC>
      elsif ($add_host2img_src and $token->[0] eq 'S' and $token->[1] eq 'img' and
	     $token->[2]->{'src'}) {img_src($token, $r, $add_host2img_src)}
      
      # Handle <FORM ACTION>
      elsif ($add_host2form_action and $token->[0] eq 'S' and 
	     $token->[1] eq 'form' and $token->[2]->{'action'}) {form_action($token, $r, 
																		 $add_host2form_action)}
	
      # Handle comments because TokeParser doesn't save the original text for them
      elsif ($token->[0] eq 'C') {print qq(<!-- $token->[-1] -->)}
      
      # Ditto for declarations
      elsif ($token->[0] eq 'D') {print qq(<!$token->[-1]>)}
	
      # Handle everything else
      else { print $token->[-1]}
      
  } # End while
} # End process_text()


# Handler
sub handler {

  my $r = shift;

  # Get configuration
  my $header_file = $r->dir_config('HeaderFile');
  my $footer_file = $r->dir_config('FooterFile');
  my $proxy_prefix = $r->dir_config('ProxyPrefix');
  my $body_attributes = $r->dir_config('BodyAttributes');
  my $strip_host = $r->dir_config('StripHost');
  my $add_host2href = $r->dir_config('AddHost2AHref');
  my $add_host2img_src = $r->dir_config('AddHost2ImgSrc');
  my $add_host2form_action = $r->dir_config('AddHost2FormAction');

  # Get the header and footer
  my $header_req = new HTTP::Request('GET' => $header_file);
  my $footer_req = new HTTP::Request('GET' => $footer_file);
  my $header_res = $UA->request($header_req);
  my $footer_res = $UA->request($footer_req);
  
  # Mangle the url for the file as needed
  my ($null, $base, $uri);
  if ($strip_host) {($null, $base, $uri) = split /\//, $r->uri, 3}
  else {$uri = $r->uri}
  $uri =~ s/^\///; # Remove leading slashes
  my $file_uri = join '/', $proxy_prefix, $uri;
  $file_uri .= q(?) . $r->args if $r->args;

  # Build the request
  my $req = new HTTP::Request($r->method => $file_uri);

  # Set headers
  my %headers = $r->headers_in;
  foreach my $header (keys %headers) {
      next if $header eq 'Connection';
      $req->push_header($header => $headers{$header});
  } # End foreach

  # Set REMOTE_ADDR, REMOTE_HOST and REMOTE_USER
  $req->push_header('REMOTE_ADDR' => $ENV{'REMOTE_ADDR'});
  $req->push_header('REMOTE_HOST' => $ENV{'REMOTE_HOST'} || $ENV{'REMOTE_ADDR'});
  $req->push_header('REMOTE_USER' => $ENV{'REMOTE_USER'});

  # Copy POST data, if any
  if ($r->method eq 'POST') {
	my $len = $r->header_in('Content-length');
	my $buf;
	$r->read($buf, $len);
	$req->content($buf);
  } # End if
  
  # Run the request
  my $res = $UA->request($req);

  if ($res->is_redirect) {
      my $location = $res->header('Location');
      my ($host) = ($location =~ m!^([^/]+//[^/]+)/!);
      if ($host eq $proxy_prefix) {
	  my $hostname = $r->server->server_hostname;
	  $location =~ s!//([^/]+)/!//$hostname/!;
	  $res->header('Location' => $location);
      } # End if
  } # End if

  # Handle all other headers
  # $res->scan(sub {$r->header_out(@_);});
  $res->scan(sub {$r->headers_out->add(@_);}); # Use this one to handle multiple headers of same name

  # Handle special headers
  $r->content_type($res->header('Content-type'));
  $r->status($res->code);
  $r->status_line($res->status_line);

  # HEAD request?
  if ($r->header_only) {
      $r->send_http_header;
      return OK;
  } # End if

  # Get the content
  my $content = $res->content_ref;

  # If it's text
  if ($r->content_type =~ /^text/) {

	# Adjust the content length to include the lenght of the header and footer
	my $length = length($header_res->content) + length($footer_res->content) + length($res->content);
	$r->header_out('Content-length' => $length);
	$r->send_http_header;
	process_text($content, $r, $header_res->content, $footer_res->content, $body_attributes, 
				 $add_host2href, $add_host2img_src, $add_host2form_action);
  } # End if
  
  else {$r->send_http_header; print $$content}
	
  return OK;

} # End handler()

1;

__END__

=head1 NAME

Apache::ProxyStuff - mod_perl header/footer/proxy module

=head1 SYNOPSIS

  <Location /foo>
   SetHandler      perl-script
   PerlHandler     Apache::ProxyStuff
   PerlSetVar      HeaderFile      http://www.bar.com:81/includes/header.html
   PerlSetVar      FooterFile      http://www.bar.com:81/includes/footer.html
   PerlSetVar      BodyAttributes  "TOPMARGIN=0 LEFTMARGIN=0 MARGINHEIGHT=0 MARGINWIDTH=0"
   PerlSetVar      ProxyPrefix http://www.foo.com
  </Location>


=head1 DESCRIPTION

Apache::ProxyStuff is module for adding headers and footers to content proxied from other web servers. Rather than sandwiching the content between the header and footer it "stuffs" the header and footer into their correct places in the content -- header after the <BODY> tag and footer before the </BODY> tag. This allows you to give content living on established servers a common look and feel without making changes to the pages.

ProxyStuff also allows you to add attributes to the <BODY> tag and manipulate links, image refs and form actions as needed.

=head1 PARAMETERS

=over 4

=item * HeaderFile

HeaderFile specifies the URL of an HTML page that will be used as the header for proxied content. It will be added after the first <BODY> tag.

Example: PerlSetVar HeaderFile http://www.bar.com/includes/header.html

=item * FooterFile

FooterFile specifies the URL of an HTML page that will be used as the footer for proxied content. It will be added before the </BODY> tag.

Example: PerlSetVar FooterFile http://www.bar.com/includes/footer.html

=item * ProxyPrefix

ProxyPrefix specifies a URL which will be prepended to the URI of the request. The new URL is the location of the content to be proxied. If /proxy/content.html is requested and ProxyPrefix is set to http://www.foo.com, the content will be proxied from http://www.foo.com/proxy/content.html.

Example: PerlSetVar ProxyPrefix http://www.foo.com

=item * BodyAttributes

BodyAttributes allows you to add or modify attributes in the <BODY> tag in the proxied content. If you specify an attribute that exists in the <BODY> tag of the proxied page, the attribute that was in the page will be overwritten with the one you specified. If your attribute does not exist in the original <BODY> tag it will simply be added to the tag.

Example: PerlSetVar BodyAttributes 'BGCOLOR="#FFFFFF" VLINK="BLUE"'

=item * StripHost

If StripHost is turned on, ProxyStuff will assume that the hostname of the server providing the content is the first part of the URI. For example, if the URI of the request is /foo/some/content.html and ProxyPrefix is set to http://www.foo.com then /foo will be stripped from the URI and a proxy request will be made to http://www.foo.com/some/content.html. 

(This is useful if your site is divided up into unique sections with their own headers/footers and each section has content proxied from multiple servers -- /foo/hr, /bar/hr and /baz/hr.)

Example: PerlSetVar StripHost Yes

=item * AddHost2AHref

=item * AddHost2ImgSrc

=item * AddHost2FormAction

AddHost2AHref, AddHost2ImgSrc and AddHost2FormAction are often used in conjunction with StripHost when your proxied content contains absolute links. ProxyStuff will add the provided text to the beginning of HREFs, SRCs and ACTIONs so these URLs are correctly mapped to ProxyStuff directories. 

For example, you set up <Location /foo> to use ProxyStuff. ProxyPrefix is set to http://www.foo.com, StripHost is turned on and AddHost2AHref, AddHost2ImgSrc and AddHost2FormAction are all set to foo. A user requests /foo/some/content.html. ProxyStuff removes /foo and requests http://www.foo.com/some/content.html. The page returned contains links such as <A HREF="/some/content.html">Link</A>. ProxyStuff will turn the link into <A HREF="/foo/some/content.html">Link</A> so when a user clicks on the link, the request will be handled by Apache::ProxyStuff.

Example: PerlSetVar AddHost2Href foo

=head1 PREREQUISITES

Apache::ProxyStuff requires mod_perl, LWP and HTML::TokeParser.

=head1 TODO

=over 4

=item * Switch to the XS version of HTML::TokeParser.

=over back

=head1 AUTHOR

Jason Bodnar <jason@shakabuku.org>

=head1 COPYRIGHT

Copyright (C) 2000, Jason Bodnar, Tivoli Systems

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut






