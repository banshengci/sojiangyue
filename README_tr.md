[English](README.md) | **Türkçe** | [简体中文](README_zh.md) | [Русский](README_RU.md)

<br>

<p align="center">
  <img src="./assets/icon/songjiang-logo.png" alt="SongJiang Reader logo" width="100" />
</p>
<h1 align="center">SongJiang Reader</h1>
<p align="center"><em>Forked from <a href="https://github.com/Anxcye/anx-reader">Anxcye/anx-reader</a></em></p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-windows%20%7C%20macos%20%7C%20iOS%20%7C%20Android-lightgrey" alt="Platformlar">
  <img src="https://img.shields.io/badge/formats-epub%20%7C%20fb2%20%7C%20mobi%20%7C%20txt%20%7C%20azw3%20%7C%20pdf-brightgreen" alt="Desteklenen Formatlar">
</p>

SongJiang Reader, kitap severler için özenle hazırlanmış bir e-kitap okuma uygulamasıdır. Güçlü yapay zeka yetenekleri ve geniş format desteğiyle okuma deneyimini daha akıllı ve odaklı hâle getirir. Modern arayüz tasarımıyla, saf okuma keyfini sunmayı hedefliyoruz.


![](./docs/images/main.jpg)


| Özellik | Detaylar | Durum |
| --- | --- | --- |
| Format Desteği | EPUB/MOBI/AZW3/FB2/TXT/PDF formatları tam destekli | ✅ |
| Platformlar Arası Senkronizasyon | Android/iOS/macOS/Windows desteği<br>Kitapları, notları ve okuma ilerlemesini WebDAV üzerinden senkronize edin | ✅ |
| AI Asistanı | Rafları okuma ilerlemesine ve tona göre düzenler<br>Derin anlayış için zihin haritaları oluşturur<br>İhtiyaca göre AI sözlük ve çeviri sağlar<br>Bakış açısı analizi ve özetler üretir | ✅ |
| Özelleştirilebilir Okuma Deneyimi | Harf, satır, paragraf ve kenar boşluklarını ayarlayın<br>Yazı tipi boyutu, stili ve kalınlığını seçin<br>Temaları, arka planları, hizalamayı ve stilleri özelleştirin | ✅ |
| Not Alanı | Çeşitli renk/stil hazır ayarları<br>Zamana veya bölüme göre sıralama, renge göre filtreleme<br>TXT/Markdown/CSV olarak dışa aktarma<br>Paylaşılabilir, özenle tasarlanmış kartlar oluşturma | ✅ |
| Okuma Analizleri | Okuma süresini takip edin<br>Günlük/haftalık/aylık/yıllık istatistikleri görüntüleyin<br>Okuma alışkanlıklarını gösteren ısı haritası | ✅ |
| Gelişmiş Özellikler | Çok sesli, hız, ton ve uyku zamanlayıcılı TTS<br>Yan yana görünümle tam kitap çevirisi<br>Kitapları bulutta saklayıp gerektiğinde indirin<br>Basitleştirilmiş/Geleneksel Çince arasında tek dokunuşla geçiş | ✅ |
| OPDS Katalogları | Yerleşik OPDS desteği ve özel katalog yönetimi | 🛠️ Çalışılıyor |


## Edinme
SongJiang Reader kaynak koddan derlenir. Platformunuz için derlemek üzere aşağıdaki [Derleme](#derleme) bölümüne bakın.


### Ekran Görüntüleri
| ![](./docs/images/wide1.png) | ![](./docs/images/wide2.png) |
| :------------------------------: | :----------------------------: |
|   ![](./docs/images/wide3.png)   |  ![](./docs/images/wide4.png)  |
|   ![](./docs/images/wide5.png)   |  ![](./docs/images/wide6.png)  |
|   ![](./docs/images/wide7.png)   |  ![](./docs/images/wide8.png)  |


| ![](./docs/images/mobile1.png) | ![](./docs/images/mobile2.png) | ![](./docs/images/mobile3.png) |
| :----------------------------: | :----------------------------: | :----------------------------: |
| ![](./docs/images/mobile4.png) | ![](./docs/images/mobile5.png) | ![](./docs/images/mobile6.png) |
| ![](./docs/images/mobile7.png) | ![](./docs/images/mobile8.png) | ![](./docs/images/mobile9.png) |

## Derleme
SongJiang Reader'ı kaynak kodundan derlemek ister misiniz? Lütfen şu adımları izleyin:
- [Flutter](https://flutter.dev) kurun.
- Projeyi klonlayın ve dizine girin.
- `flutter pub get` komutunu çalıştırın.
- Çok dilli dosyaları oluşturmak için `flutter gen-l10n` çalıştırın.
- Riverpod kodunu oluşturmak için `dart run build_runner build --delete-conflicting-outputs` çalıştırın.
- Uygulamayı başlatmak için `flutter run` komutunu çalıştırın.

Flutter sürüm uyumsuzluklarıyla karşılaşabilirsiniz. Detaylar için [Flutter dokümantasyonuna](https://flutter.dev/docs/get-started/install) bakın.


## Bir Sorunla Karşılaştım, Ne Yapmalıyım?
- [Sorun Giderme](./docs/troubleshooting.md#English) bölümünü kontrol edin.


## Lisans
Bu proje [MIT Lisansı](./LICENSE) ile lisanslanmıştır.

Sürüm 1.1.4'ten itibaren, SongJiang Reader projesinin açık kaynak lisansı MIT Lisansından GNU Genel Kamu Lisansı sürüm 3 (GPLv3) olarak değiştirilmiştir.

Sürüm 1.2.6'dan sonra seçim ve vurgulama özelliği yeniden yazılmış ve açık kaynak lisansı GPL-3.0 Lisansından MIT Lisansına dönmüştür. Tüm katkıda bulunanlar bu değişikliği kabul etmiştir (#116).

## Teşekkürler
[foliate-js](https://github.com/johnfactotum/foliate-js), MIT lisanslıdır ve e-kitap görüntüleyici olarak kullanılmaktadır. Böylesine harika bir proje sunduğu için yazara teşekkür ederiz.

[foliate](https://github.com/johnfactotum/foliate), GPL-3.0 lisanslıdır; seçim ve vurgu özelliği bu projeden ilham almıştır. Ancak 1.2.6 sürümünden beri bu özellik yeniden yazılmıştır.

Ve birçok [diğer açık kaynak proje](./pubspec.yaml); katkıda bulunan tüm yazarlara teşekkürler.
