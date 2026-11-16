# WaveAce pro macOS

Nativní aplikace SwiftUI pro LeCroy WaveAce 224. Připojení Ethernet / VICP na TCP portu 1861. Bez externích knihoven a bez instalace VISA.

## Spuštění

Otevři `build/WaveAce.app`, zadej IP adresu (výchozí `192.168.0.100`) a klikni na **Připojit**. Pokud macOS požádá o přístup do místní sítě, povol jej a připojení případně zopakuj. Oprávnění najdeš také v Nastavení systému → Soukromí a zabezpečení → Místní síť → WaveAce. Aplikace při připojení pouze čte aktuální nastavení a průběhy. Ovládací prvky Run, Stop, Single, časová základna, citlivost kanálů a trigger mění nastavení přístroje.

- Zapnutí **Vstup** u kanálu ovládá jeho zapnutí v osciloskopu.
- Ikona oka pouze skryje průběh v aplikaci a vynechá jeho přenos.
- Pauza u grafu zastaví přenos do Macu; osciloskop pokračuje v měření.
- Graf ukazuje celý přenesený záznam, případně přiblížený výsek. Časová osa používá údaje z WAVEDESC. Rozsah přeneseného záznamu se může lišit od rozsahu displeje přístroje.
- Vpp a RMS se počítají z celého přeneseného záznamu. Kurzory měří časový rozdíl ve viditelném výseku; `1/Δt` je převrácená hodnota tohoto rozdílu.
- V části **Přenos do Macu → Vzorky** lze zvolit plný záznam nebo každý 4., 10. či 20. vzorek. Při původních 12 268 vzorcích se přenáší 12 268 / 3 067 / 1 226 / 613 vzorků na kanál. Jde o rovnoměrné vybírání vzorků přes záznam; může vynechat krátké špičky a zkreslit Vpp/RMS. Pro podrobné měření vyber plný záznam. Akvizice osciloskopu se tím nemění.
- CSV obsahuje pro každý viditelný kanál vlastní dvojici sloupců čas v sekundách / napětí ve voltech. Exportují se pouze skutečně přenesené vzorky podle zvolené volby **Vzorky**. PNG ukládá aktuální graf.
- Firmware WA224 ponechává při řidším přenosu v deskriptoru původní délku i časový krok. Dekodér zohledňuje přenosový faktor, skutečnou délku odpovědi a odpovídajícím způsobem upravuje časovou osu. Při běžném odpojení se obnoví původní nastavení přenosu.
- Kanály se stahují postupně. Při běžícím měření nemusí pocházet ze stejné akvizice. Pro porovnávání jedné události použij Single a po dokončení přenos, případně zastav akvizici tlačítkem Stop.

## Sestavení a kontrola

Vyžaduje macOS 14+ a Xcode Command Line Tools se Swiftem 5.9+. Ověřeno na Apple Silicon, macOS 26.7.2, Xcode 27.2.

```sh
bash Tools/build-app.sh
swift test
swift run WaveAceCheck 192.168.0.100
swift run WaveAceCheck 192.168.0.100 --stride 10
```

`WaveAceCheck` čte identifikaci, nastavení a průběhy zapnutých kanálů. Dočasně nastavuje faktor přenosu a při úspěšném dokončení obnoví původní hodnotu. Pythonový nástroj `Tools/scope_probe.py` slouží k jednotlivým diagnostickým dotazům (např. `python3 Tools/scope_probe.py '*IDN?'`).

## Rozsah první verze

Ethernet, až čtyři kanály, automatický přenos, Run/Stop/Single, časová základna, citlivost kanálů, zdroj/hrana/úroveň triggeru, přiblížení a posuv, časové kurzory, Vpp/RMS, CSV a PNG. Nastavení se průběžně znovu čte z přístroje. Po ztrátě spojení zůstane viditelný poslední záznam a připojení lze obnovit ručně.

USB zatím není implementováno. Sekvenční, RIS a průběhy se dvěma datovými poli jsou odmítnuty, aby se nezobrazily s nesprávnou interpretací. Uložení nastavení přístroje, FFT a pokročilé triggery nejsou součástí této verze. Vzorkovací frekvence osciloskopu je nezávislá na rychlosti obnovování přenosu do Macu.

## Kompatibilita a zdroje

Na skutečném přístroji ověřena identifikace `LECROY,WA224` s firmwarem **5.05.02.14**, VICP na portu 1861 a přenos `C1:WF? ALL`. Původní údaj o firmwaru byl správný; seznam kompatibility EasyScope na webu výrobce není úplným seznamem všech firmwarů tohoto přístroje.

Ověření 16. 11. 2026: úspěšné sestavení Debug i Release, sedm automatických testů dekodéru bez chyb (včetně řidšího přenosu a jeho časové osy), dekódování skutečného záznamu s 12 268 vzorky, načtení CH1/CH2 přes nativní komunikační knihovnu a následně živé zobrazení CH1–CH4 v aplikaci přibližně rychlostí 1 snímek/s. Exporty a všechny kombinace nastavení dosud nemají kompletní ruční ověření. Jde o první funkční verzi.

- [EasyScope – oficiální podpora](https://www.teledynelecroy.com/support/softwaredownload/easyscope.aspx)
- [WaveAce 1000/2000 Remote Control Manual](https://cdn.teledynelecroy.com/files/manuals/wa1k2k_remote-control_manual.pdf) – pomocný popis příkazů a struktury WAVEDESC; není deklarací kompatibility modelu 224. Použité dotazy byly ověřeny na skutečném WA224.
- [WaveAce EasyScope Operator's Manual](https://cdn.teledynelecroy.com/files/manuals/es-om-e_reva.pdf)

Výsledná aplikace je lokálně podepsána ad hoc; není distribučním balíčkem s Apple Developer ID ani notarizací. Všechny naměřené hodnoty zůstávají lokálně.
