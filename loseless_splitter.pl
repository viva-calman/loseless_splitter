#!/usr/bin/perl

#use warnings;
use strict;
use Data::Dumper;
use utf8;

my $album_info = {};
my @filelist;
my $dirs=0;

=encoding utf8
=head1 Использование:

=head2 Как это использовать?
    Просто перейти в директорию с аудиофайлами и cue-файлами и запустить скрипт. Разрезаные (и при необходимости сконвертированные) файлы будут находиться в этой же директории. Оригинал файлов не удаляется. Для каждого файла в секции FILE cue-таблицы создается поддиректория Disk-N. Может быть некорректное поведение, если в одном треке несколько композиций, а в остальных - по одной. В этом случае разрезание будет корректным, однако появится лишняя директория.

=head2 Зависимости:

    sox - для разрезания
    flac - для кодирования
    ffmpeg - Для перегона ape во flac
    wvunpack - для распаковки wavpack
    enca - Для определения кодировок
    7z - для распаковки wv.iso

=head2 Примечания:
    
    Floating point PCM перекодируется в signed integer. Причины этого в том, что я не вижу смысла в таком выпендреже. Я никогда не услышу разницу, зато имею трудности при кодировании. Спасибо за понимание.

=cut

#my $cue = shift @ARGV;

work_dir();

#print "\n";
#print Dumper(%{$album_info});

splitting();

#
# Обработка директории
#
sub work_dir {
    opendir my $workdir,".";
    @filelist = readdir($workdir);
    closedir $workdir;

    my $cue_count = grep { m/.*\.cue$/i } @filelist;
    my $file_count = grep { m/.*\.(flac|ape|wv)$/i } @filelist;
    
    for my $i (@filelist)
    {
        print "$i\n";
        if ($i =~ m/.*\.wv\.iso/)
        {
            `7z x "$i" && mv "$i" "$i.old"`;
            work_dir();
            return 0
        }
    }

    print "cue found: $cue_count\nfiles found: $file_count\n";



    if ($cue_count > $file_count)
    {
        print "Multiple cue found\nSearch UTF-8 cue\n";
        for my $k (grep { m/.*\.cue$/i } @filelist)
        {
                cue_analitic($k);
        }
        my $rep_files = {};
        my $rep_ind;
        #
        # Удаляем дубликаты с разными расширениями
        #
        for my $rep (keys $album_info->{FILE})
        {
            $rep_ind = $rep;
            $rep_ind =~ s/(\.flac|\.ape|\.wav|\.wv)"$//i;
            $rep_files->{$rep_ind}->{$rep} = 1;       
        }
        for my $rep_proc (keys %{$rep_files})
        {
            for my $rp (keys $rep_files->{$rep_proc})
            {
                if ($rp =~ m/.*\.wav"$/i)
                {
                    print "~";
                    delete $album_info->{FILE}->{"$rp"};
                }
            }
        }
    }
    else
    {
        if($cue_count == $file_count)
        {
            print "Numbers of cue equal numbers of files\ncheck count of images\n";
            if ($cue_count == 1)
            {
                print "Ok! Run!\n";
                cue_analitic(grep { m/.*\.cue$/i } @filelist);
            }
            else
            {
                print "Need to create subdirs\n";
                for my $j (grep { m/.*\.cue$/i } @filelist)
                {
                    cue_analitic($j);
                }
            }
        }
        else
        {
            print "Need cue analyzing\n";
            cue_analitic(grep { m/.*\.*cue$/i } @filelist) 
        }
    }
}


sub cue_enc {
    my $cue = shift;
    my $enc = `enca "$cue"`;
    if ($enc =~ m/.*UTF-8/ or $enc =~ m/7bit ASCII.*/)
    {
        return $cue;
    }
    else
    {
        return undef;
    }
}


#
# Парсинг Cue-файла
#
sub cue_analitic {
    my $cue_name = shift;
    my $tracks = 0;
    my ($file,$track,$cuefile);
    my $perf = 0;


    if(cue_enc($cue_name))
    {
        open $cuefile, $cue_name;
    }
    else
    {
        open $cuefile, "cat \"$cue_name\"|iconv -f CP1251|";
    }
    while(<$cuefile>)
    {
        #print $_;
        s/\r//;
        if(m/REM DATE (\d{4})/i)
        {
            $album_info->{'DATE'}=$1;
        }
        if(m/PERFORMER (.*)/i && !$perf)
        {
            $album_info->{'PERFORMER'}=$1;
            $perf = 1;
            next;
        }
        if(m/TITLE (.*)/i && !$tracks)
        {
           $album_info->{'ALBUM'}=$1;
        }
        if(m/GENRE (.*)/i)
        {
           $album_info->{'GENRE'}=$1;
        }
        if(m/FILE (.*) WAVE/i)
        {
            $album_info->{'FILE'}->{$1}={};
            $tracks = 1;
            $file = $1;
        }
        if(m/TRACK (\d*) AUDIO/i)
        {
            $album_info->{FILE}->{$file}->{$1}={};
            $track = $1;       
        }
        if(m/TITLE (.*)/i && $tracks)
        {
            $album_info->{FILE}->{$file}->{$track}->{'TITLE'}=$1;
        }   
        if(m/INDEX 01 (.*)/i)
        {
            $album_info->{FILE}->{$file}->{$track}->{'INDEX 01'}=$1;
        }
        if(m/PERFORMER (.*)/i && $perf)
        {
            $album_info->{FILE}->{$file}->{$track}->{'PERFORMER'}=$1;
        }
           

        
    }
    close $cuefile;
}
#
# Выбираем файл для разрезания
#
=head2 Функция splitting
    Внешняя обертка для разрезания файлов.
    Проверяем количество файлов для обработки. Треки из каждого образа помещаются в отдельную директорию, число директорий соответствует количеству файлов. Если файл один, дополнительные директории не создаются
    Если в .cue файле записано имя файла с расширением .wav, ищем в списке файлов файл с таким же именем, но с другим расширением. Каждый обнаруженный файл передается в функцию process().
=cut

sub splitting {
    if(1 < scalar keys $album_info->{FILE})
    {
        print "Creating additional dirs\n";
        $dirs = 1;
    }
    for my $i (sort keys $album_info->{FILE})
    {
        print "File in process: $i\n";
        my $temp_i = $i;
        $temp_i =~ s/^"//;
        $temp_i =~ s/"$//;
        $temp_i =~ s/(\[|\]|\(|\)|\\|\+)/\\$1/g;
        if( -e "$temp_i" )
        {
            print "Found, process\n";
            process($temp_i,$i);
        }
        else
        {
            print "Not found, try another extensions\n";
            $temp_i =~ s/\.(wav|ape|flac|wv)$//i;
            my ($j) = grep { m/$temp_i.(flac|ape|wv)$/i } @filelist;
            if( -e "$j")
            {
                print "Found: $j, process\n";
                process($j,$i);
            }
            else
            {
                print "File not found\nNot splitted\n";
            }
        }
        $dirs++;
    }
}

=head2 Функция process
    
=cut

sub process {
    my $filename = shift;
    my $filekey = shift;
    if($dirs != 0) # && 1 < scalar keys $album_info->{FILE}->{$filekey})
    {
        mkdir "Disc $dirs";
    }
    if (1 == scalar keys $album_info->{FILE}->{$filekey})
    {
        print "Single track in file\n";
    }
    if ($filename =~ m/.*\.flac$/)
    {
            split_flac($filename,$filekey);
    }
    elsif ($filename =~ m/.*\.ape/)
    {
        print "Convert .ape to .flac";
        my $flacname = $filename;
        $flacname =~ s/\.ape$/\.flac/;
        system("ffmpeg -i \"$filename\" \"$flacname\"");
        split_flac($flacname,$filekey);
    }
    elsif ($filename =~ m/.*\.wv/)
    {
        my $wavname = $filename;
        my $wvtype = `soxi -e "$filename"`;
        if($wvtype =~ m/Floating Point WavPack/ or $wvtype =~ m/Floating Point PCM/)
        {
            print "\nWARNING!!!\n Convert floating point PCM into signed integer!\n";
        }
        $wavname =~ s/\.wv$/\.wav/;
        my $flacname = $filename;
        $flacname =~s/\.wv/\.flac/;
        `wvunpack "$filename" && ffmpeg -i "$wavname" "$flacname"`;
        split_flac($flacname,$filekey);
    }
    else
    {
        die "Unknown file format $filename\n";
    }
}

sub split_flac {
    my $filename = shift;
    my $filekey = shift;
    for my $i (sort keys %{$album_info->{FILE}->{$filekey}})
    {
        print "Splitting file #$i\n";
        split_track($filename,$filekey,$i,"--encoding signed-integer");
        my $out_flac;
        my $performer;
        if(defined $album_info->{FILE}->{$filekey}->{$i}->{PERFORMER})
        {
            $performer = $album_info->{FILE}->{$filekey}->{$i}->{PERFORMER};
        }
        else
        {
            $performer = $album_info->{PERFORMER};
        }
        my $date = $album_info->{DATE};
        my $genre = $album_info->{GENRE};
        my $album = $album_info->{ALBUM};
        $album = " " if !defined $album;
        $genre = " " if !defined $genre;
        $date = " " if !defined $date;
        my $track_title = $album_info->{FILE}->{$filekey}->{$i}->{TITLE};
        my $performer_f = $performer;
        my $title_f = $track_title;
        $performer_f =~ s/\///g;
        $title_f =~ s/\///g;


        if ($dirs != 0)
        {
            $out_flac = "Disc $dirs/$i - $performer_f - $title_f.flac"
        }
        else
        {
            $out_flac = "$i - $performer_f - $title_f.flac";

        }
        $out_flac =~ s/"|\\|\:|\*|\?|\<|\>//g;
        $out_flac =~ s/`/\\`/g;
        $genre =~ s/`/\\`/g if defined $genre;
        #
        # Удаление замыкающих кавычек
        #
        $genre =~ s/^"(.*)"$/$1/g if defined $genre;
        $album =~ s/^"(.*)"$/$1/g if defined $album;
        $performer =~ s/^"(.*)"$/$1/g if defined $performer;
        $track_title =~ s/^"(.*)"$/$1/g if defined $track_title;


        #
        # Экранирование Внутренних кавычек
        #
        $genre =~ s/"//g if defined $genre;
        $album =~ s/"/\\"/g if defined $album;
        $performer =~ s/"/\\"/g if defined $performer;
        $track_title =~ s/"/\\"/g if defined $track_title;

        $track_title =~ s/`/\\`/g if defined $track_title;
        $performer =~ s/`/\\`/g if defined $performer;
        $album =~ s/`/\\`/g if defined $album;
        my $command = qq{
            flac  \\
            --compression-level-8 \\
            --force \\
            --output-name "./$out_flac" \\
            --tag date="$date" \\
            --tag genre="$genre" \\
            --tag album="$album" \\
            --tag tracknumber="$i" \\
            --tag artist="$performer" \\
            --tag title="$track_title" \\
            temp.wav && rm temp.wav
            };
#            print "Use: $command";
        `$command`;
    }

}

sub split_track {
    my $work_file = shift;
    my $filekey = shift;
    my $trackno = shift;
    my $encoding = shift;
    my $begin = $album_info->{FILE}->{$filekey}->{$trackno}->{'INDEX 01'};
    $begin =~ s/:(\d{2})$/\.$1/;
    $trackno++;
    my $end;


    if (defined $album_info->{FILE}->{$filekey}->{$trackno}->{'INDEX 01'})
    {
        $end = $album_info->{FILE}->{$filekey}->{$trackno}->{'INDEX 01'};
        $end =~ s/:(\d{2})$/\.$1/;
    }
    else
    {
        $end = `soxi -s "$work_file"`;
        $end =~s/\n/s/;

    }
        my $command=qq{
            sox --multi-threaded \\
            --buffer 131072 \\
            --no-dither \\
            -q "$work_file" \\
            -t wav $encoding \\
            temp.wav \\
            trim $begin =$end
    };
    #print "$command\n";
    `$command`;

}

