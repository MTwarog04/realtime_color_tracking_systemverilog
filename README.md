# System śledzenia obiektów w czasie rzeczywistym

Autorzy: Maciej Nowak, Mikołaj Twaróg

Projekt realizuje śledzenie niebieskiego obiektu za pomocą kamery OV7670 i dwóch
płytek Basys 3. Pierwsza płytka zajmuje się obsługą kamery, analizą obrazu oraz
wyświetlaniem podglądu VGA. Druga odbiera pozycję wykrytego obiektu i steruje
dwoma serwomechanizmami MG90S, na których znajduje się moduł laserowy.

W repozytorium znajdują się dwa osobne warianty przeznaczone do wygenerowania
bitstreamów dla płytki kamery i płytki serwa. Zostawiliśmy również starszą wersję
jednopłytkową jako punkt odniesienia.

```text
Basys 3 z kamerą                                  Basys 3 z serwami
----------------                                  ------------------
OV7670 -> analiza obrazu -> UART TX --- JA1 ---> UART RX -> sterownik serw -> PWM
                                   GND --- GND --->
```

Pomiędzy płytkami nie jest przesyłany cały obraz. Płytka kamery wysyła jedynie
informację o nowej ramce, flagę poprawnego wykrycia celu oraz jego współrzędne:
9-bitową współrzędną X i 8-bitową współrzędną Y.

## Sposób działania

Po uruchomieniu układu kamera OV7670 jest konfigurowana przez interfejs SCCB.
Obraz wejściowy 640×480 jest zmniejszany do rozdzielczości roboczej 320×240,
a następnie analizowany w przestrzeni barw YCbCr.

Kolejne etapy przetwarzania obejmują:

1. wykrywanie pikseli należących do niebieskiego obiektu,
2. usuwanie pojedynczych zakłóceń z maski,
3. analizę znalezionych obszarów pod względem rozmiaru, proporcji i wypełnienia,
4. wyznaczenie środka najlepszego obiektu,
5. wygładzenie jego położenia pomiędzy kolejnymi ramkami,
6. wysłanie współrzędnych do płytki sterującej serwami.

Podgląd jest wyświetlany przez VGA w rozdzielczości 1024×768 przy 60 Hz.
Czerwony znacznik pokazuje wyznaczony środek obiektu. Płytka serwa odbiera
pakiety UART, sprawdza CRC i dopiero wtedy aktualizuje pozycję mechanizmu.

## Połączenie sprzętu

Do połączenia obu płytek wystarczą dwa przewody:

1. `JA1` płytki kamery -> `JA1` płytki serwa,
2. pin `GND` złącza Pmod płytki kamery -> pin `GND` płytki serwa.

Jako masę można wykorzystać pin 5 albo 11 złącza Pmod. Nie należy łączyć ze
sobą pinów 3,3 V ani VCC obu płytek.

Serwomechanizmy powinny być zasilane z osobnego, stabilnego źródła 5 V. Masa
tego zasilacza musi być połączona z masą płytki sterującej serwami.

UART pracuje z szybkością 100 000 bodów. Wartość została dobrana tak, aby zegar
40 MHz dzielił się przez nią bez reszty, co daje 400 taktów zegara na jeden bit.
Przesłanie całego siedmiobajtowego pakietu zajmuje około 700 µs, czyli znacznie
mniej niż czas jednej ramki obrazu.

## Najważniejsze pliki projektu

| Część projektu | Pliki |
| --- | --- |
| Komunikacja między płytkami | `rtl/communication/tracking_uart_pkg.sv`, `rtl/communication/tracking_uart_tx.sv`, `rtl/communication/tracking_uart_rx.sv` |
| Płytka kamery | `rtl/top/top_camera.sv`, `fpga/rtl/top_camera_basys3.sv`, `constraints/top_camera_basys3.xdc` |
| Płytka serwa | `rtl/top/top_servo.sv`, `fpga/rtl/top_servo_basys3.sv`, `constraints/top_servo_basys3.xdc` |

Moduł `top_camera` zawiera obsługę kamery, przetwarzanie obrazu, tor VGA oraz
nadajnik UART. Moduł `top_servo` odbiera sprawdzony pakiet i przekazuje pozycję
do modułów `servo_controller` oraz `pwm_generator`.

## Format pakietu UART

Pakiet ma następującą postać:

```text
A5 5A SEQ X_LO FLAGS Y CRC8
```

Znaczenie pól:

- `A5 5A` - dwa bajty początku pakietu,
- `SEQ` - numer kolejnego pakietu,
- `X_LO` - osiem młodszych bitów współrzędnej X,
- `FLAGS[0]` - najstarszy bit współrzędnej X, czyli `X[8]`,
- `FLAGS[1]` - flaga `target_valid`,
- `Y` - współrzędna pionowa,
- `CRC8` - suma kontrolna CRC-8/ATM.

Płytka serwa zmienia pozycję tylko po odebraniu kompletnego pakietu z poprawnym
CRC. Jeśli przez 0,5 s nie pojawi się poprawny pakiet, odbiornik zeruje flagę
`target_valid` i oznacza połączenie jako nieaktywne.

## Uruchamianie symulacji

Po wcześniejszym wykonaniu `source env.sh` można wyświetlić listę testów albo
uruchomić wszystkie testy automatyczne:

```bash
./tools/run_simulation.sh -l
./tools/run_simulation.sh -a
```

Testy sprawdzają między innymi:

- czasy przebiegów PWM,
- ruch serw i ograniczenia pozycji,
- transmisję UART oraz obsługę błędnego CRC,
- wykrywanie koloru i obliczanie środka obiektu,
- odbiór danych z OV7670,
- pełną ramkę czasową VGA.

Nieudany test jest oznaczany komunikatem `FAILED`.

## Automatyczne generowanie dwóch bitstreamów

Po przygotowaniu środowiska poleceniem `source env.sh` należy uruchomić:

```bash
./tools/generate_bitstream.sh
```

Skrypt tworzy dwa niezależne projekty Vivado i zapisuje wyniki w katalogu
`results`:

```text
results/top_camera_basys3.bit
results/top_servo_basys3.bit
results/warning_summary.log
```

Raporty timingu i wykorzystania zasobów pozostają odpowiednio w katalogach
`fpga/build/camera` i `fpga/build/servo`.

Po podłączeniu wybranej płytki można ją zaprogramować poleceniem:

```bash
./tools/program_fpga.sh camera
./tools/program_fpga.sh servo
```

## Generowanie bitstreamów w Vivado GUI

Jeżeli projekt jest uruchamiany bez skryptu, trzeba utworzyć dwa osobne projekty
RTL w Vivado. Najlepiej zapisać je poza katalogiem `fpga`, na przykład:

```text
vivado_projects/camera/basys_camera.xpr
vivado_projects/servo/basys_servo.xpr
```

Podczas dodawania źródeł należy odznaczyć opcję **Copy sources into project**.
Dzięki temu oba projekty korzystają bezpośrednio z plików znajdujących się w
repozytorium i nie tworzą dodatkowych kopii kodu.

### Projekt kamery

Jako moduł najwyższego poziomu należy ustawić `top_camera_basys3`, a jako plik
ograniczeń dodać:

```text
constraints/top_camera_basys3.xdc
```

Pliki źródłowe należy dodać w następującej kolejności:

```text
rtl/display/vga_pkg.sv
rtl/camera/ycbcr_classifier.sv
rtl/camera/mask_despeckle_filter.sv
rtl/camera/centroid_accumulator.sv
rtl/camera/smooth_tracker.sv
rtl/camera/ov7670_capture.sv
rtl/camera/ov7670_configurator.sv
rtl/display/vga_timing.sv
rtl/display/video_framebuffer.sv
rtl/display/vga_frame_renderer.sv
rtl/display/top_vga.sv
rtl/communication/tracking_uart_pkg.sv
rtl/communication/tracking_uart_tx.sv
rtl/top/top_camera.sv
fpga/rtl/top_camera_basys3.sv
```

Po wykonaniu **Generate Bitstream** otrzymany plik należy wgrać do płytki
połączonej z kamerą OV7670 i monitorem VGA.

### Projekt serwa

Jako moduł najwyższego poziomu należy ustawić `top_servo_basys3`, a jako plik
ograniczeń dodać:

```text
constraints/top_servo_basys3.xdc
```

W projekcie powinny znaleźć się następujące pliki:

```text
rtl/communication/tracking_uart_pkg.sv
rtl/communication/tracking_uart_rx.sv
rtl/servo/servo_controller.sv
rtl/servo/pwm_generator.sv
rtl/top/top_servo.sv
fpga/rtl/top_servo_basys3.sv
```

Wygenerowany bitstream należy wgrać do płytki odpowiedzialnej za sterowanie
serwomechanizmami.

## Diody diagnostyczne płytki serwa

| Dioda | Znaczenie |
| --- | --- |
| `LD0` | W ciągu ostatnich 0,5 s odebrano poprawny pakiet |
| `LD1` | Od ostatniego resetu odebrano przynajmniej jeden błędny pakiet |
| `LD2` | Ostatni poprawny pakiet zawierał wykryty cel |
| `LD3` | Aktualny poziom linii UART RX; w stanie spoczynkowym powinna być wysoka |

## Tryb diagnostyczny kamery

Tryb diagnostyczny włącza się przełącznikiem `SW15`. Przełączniki `SW14:SW13`
pozwalają wybrać wyświetlany kanał: Y, Cb, Cr albo moduł chrominancji. `SW12`
służy do zmiany kolejności składowych chrominancji, jeśli kamera przesyła je w
odwrotnej kolejności.
