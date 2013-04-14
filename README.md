# TVRage2Org

TVRage2Org is a ruby script that automatically fetches your favourite
shows on [TVRage](http://www.tvrage.com) and make it into an
[Org](http://orgmode.org) file to be part of your agenda files. You
have something like that:

![agenda screenshot](images/agenda.png)

Your favourite shows are stored in a
[Yaml](http://en.wikipedia.org/wiki/YAML) file. See
[config.yaml](config.yaml) for an example.

## Examples

Custom configuration file, no debug messages and results in an org file:

```bash
ruby main.rb -f myconfigfile.yaml 2> /dev/null > ~/Org/series.org
```

Same thing with the -o option:

```bash
ruby main.rb -f myconfigfile.yaml -o ~/Org/series.org
```

This script is likely to be run by a cron task. As an example, I
place the bash script [TVrage2org](TVrage2org) in /etc/cron.daily/.

## License

Copyright (C) 2012 Sylvain Rousseau <thisirs at gmail dot com>

Author: Sylvain Rousseau <thisirs at gmail dot com>

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
