#!/usr/bin/perl -w
require maxhtmlparsing;
require maxindexing;
use strict;
use open qw/:std :utf8/;
use MongoDB;
use Encode;

my @motsVides = separer(lireTexte('motsVides'));

=pod
Initialisation
=cut
# On se connecte à la base de données
my $client = MongoDB::MongoClient -> new;
my $db = $client -> get_database('Wikinews');
# On se connecte à l'index direct et à l'index inversé
my $inverse = $db -> get_collection('Index inverse');
my $direct = $db -> get_collection('Index direct');
# On les vide
$inverse -> remove();
$direct -> remove();
# On instancie un index direct et un un index inverse
my %indexDirect = ();
my %indexInverse = ();

=pod
Parsage des fichiers HTML
=cut
# On récupère les fichiers HTML dans le dossier data
opendir (DIR, 'data/') or die $!;
# On regarde chaque fichier HTML
while (my $fichier = readdir(DIR)) {
	# On vérifie que c'est bien un fichier HTML 
	if ($fichier =~ /(.*)\.html/) {
		# On récupère le nom du document (sans le ".html")
		my $nom = Encode::decode('utf8', $1);
		# On ouvre le fichier
		open FILE, '<', "data/$fichier" or die $!;
		# On met chaque ligne dans un tableau
		my @data = <FILE>;
		# On joint les lignes et on enlève les espaces en trop
		my $contenu = maxhtmlparsing::clean(@data);
		# On cherche la dernière date de modification de l'article
		$indexDirect{$nom}{'dateModification'} = maxhtmlparsing::dateModification($contenu);
		# On cherche les catégories de l'article
		$indexDirect{$nom}{'categories'} = [maxhtmlparsing::categories($contenu)];
		# On cherche les sources de l'article
		$indexDirect{$nom}{'sources'} = [maxhtmlparsing::sources($contenu)];
		# On récupère le body
		my $body = maxhtmlparsing::body($contenu);
		# On enlève les liens vers les réseaux sociaux
		$body = maxhtmlparsing::enleverPartage($body);
		# On récupère les paragraphes entre les balises p
		$body = maxhtmlparsing::paragraphes($body);
		# On enlève le code HTML
		$body = maxhtmlparsing::retirerHTML($body);
		# On récupère la date d'écriture de l'article
		$indexDirect{$nom}{'dateEcriture'} = maxhtmlparsing::date($body);
		# On sauvegarde le body dans un dossier
		open my $fichierTexte, '>', 'bodies/'.$nom.'.txt' or die $!;
		print {$fichierTexte} $body;
	}
}

=pod
Indexation des fichiers textes
=cut
# On index les bodys extraits
indexerCollection('bodies/');

=pod
Stockage dans la base MongoDB
=cut
# On stocke l'index direct
foreach my $document (keys %indexDirect) {
	$direct -> save({
		'_id' => $document,
		'dateModification' => $indexDirect{$document}{'dateModification'},
		'categories' => $indexDirect{$document}{'categories'},
		'sources' => $indexDirect{$document}{'sources'},
		'dateEcriture' => $indexDirect{$document}{'dateEcriture'},
		'nbMots' => $indexDirect{$document}{'nbMots'},
		'longueur' => $indexDirect{$document}{'longueur'},
		'mots' => $indexDirect{$document}{'mots'}
		});
}
# On stocke l'index inverse
foreach my $mot (keys %indexInverse) {
	$inverse -> save({
		'_id' => $mot,
		'nbDocuments' => $indexInverse{$mot}{'nbDocuments'},
		'documents' => $indexInverse{$mot}{'documents'}
		});
}

=pod
Les fonctions suivantes ne sont pas dans le module
maxparsing car elles nécessitent des variables globales.
=cut
sub indexer {
	# Paramètres
	my ( $idDoc, $chemin ) = @_;
	# On prend le contenu du document
	my $mots = lireTexte($chemin);
	# On le nettoie
	$mots = minuscules($mots);
	$mots = ponctuation($mots);
	foreach my $mot (@motsVides) {
		$mots =~ s/\b$mot\b/ /gi;
		$mots =~ s/\s+/ /g;
	}
	my @mots = lemmatisation($mots);
	#my @mots = separer($mots);
	# On cherche la frequence des mots
	my %frequence = frequence(@mots);
	# Index direct
	foreach my $terme ( keys %frequence ) {
		my $frequenceMot = $frequence{$terme};
		$indexDirect{$idDoc}{'mots'}{$terme} = $frequenceMot;
		$indexDirect{$idDoc}{'nbMots'} += 1;
		$indexDirect{$idDoc}{'longueur'} += $frequenceMot;
	}
	# Index inverse
	foreach my $terme ( keys %frequence ) {
		$indexInverse{$terme}{'documents'}{$idDoc} = $frequence{$terme};
		$indexInverse{$terme}{'nbDocuments'} += 1;
	}
}
sub indexerCollection {
	# Paramètres
	my ( $chemin ) = @_;
	# On récupère les fichiers
	my @fichiers = lister($chemin);
	# On parcourt chaque fichier
	foreach my $fichier (@fichiers) {
		$fichier =~ /.+\/+(.+).txt/;
		my $nom = Encode::decode('utf8', $1);
		indexer($nom, $fichier);
	}
}
