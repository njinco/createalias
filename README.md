# createalias

Interactive alias manager for bash.

## Usage

Source the script so it can update your current shell session:

```bash
source ./crealias.sh
```

Permanent aliases are saved to `$HOME/.bashrc`, `$HOME/.bash_aliases`, or
both, depending on your selection. The script adds a `.bash_aliases` loader
to `.bashrc` when needed. This also applies to Bash in Termux: choose **yes**
for “Make this alias permanent?” to keep it across sessions.

## Tests

```bash
python3 -m unittest discover -s tests
```

## Download

```bash
curl -fsSL https://raw.githubusercontent.com/njinco/createalias/main/crealias.sh -o crealias.sh
```

## License

Licensed under the GNU Affero General Public License v3.0 or later
(AGPL-3.0-or-later). See `LICENSE`.
