import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter/foundation.dart';

class AdManager {
  static final AdManager _instance = AdManager._internal();
  static AdManager get instance => _instance;
  AdManager._internal();

  InterstitialAd? _interstitialAd;
  bool _isInterstitialAdReady = false;
  VoidCallback? _onInterstitialAdDismissed;

  BannerAd? _bannerAd;
  bool _isBannerAdReady = false;

  NativeAd? _nativeAd;
  bool _isNativeAdReady = false;

  RewardedAd? _rewardedAd;
  bool _isRewardedAdReady = false;

  // Ad Unit IDs
  static String get interstitialAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-8899080422129818/6006346319';
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/4411468910'; // iOS Test ID
    } else {
      throw UnsupportedError('Unsupported platform');
    }
  }

  static String get bannerAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-8899080422129818/7643679858';
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/2934735716'; // iOS Test ID
    } else {
      throw UnsupportedError('Unsupported platform');
    }
  }

  static String get nativeAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-8899080422129818/9023978624';
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/2247696110'; // iOS Test ID
    } else {
      throw UnsupportedError('Unsupported platform');
    }
  }

  static String get rewardedAdUnitId {
    if (Platform.isAndroid) {
      return 'ca-app-pub-8899080422129818/2236872096';
    } else if (Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/1712485313'; // iOS Test ID
    } else {
      throw UnsupportedError('Unsupported platform');
    }
  }

  void initialize() {
    MobileAds.instance.initialize();
  }

  // Rewarded Ad Methods
  void loadRewardedAd() {
    if (_isRewardedAdReady) return;
    RewardedAd.load(
      adUnitId: rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isRewardedAdReady = true;
          debugPrint('AdManager: Rewarded ad loaded.');
        },
        onAdFailedToLoad: (err) {
          _isRewardedAdReady = false;
          debugPrint('AdManager: Rewarded ad failed to load: $err');
        },
      ),
    );
  }

  void showRewardedAd({
    required Function(RewardItem) onAdRewarded,
    required VoidCallback onAdFailed,
  }) {
    if (!_isRewardedAdReady || _rewardedAd == null) {
      debugPrint('AdManager: Rewarded ad not ready.');
      onAdFailed();
      loadRewardedAd(); // Try to load another one
      return;
    }

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) =>
          debugPrint('AdManager: Rewarded ad showed.'),
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _isRewardedAdReady = false;
        loadRewardedAd(); // Pre-load next ad
      },
      onAdFailedToShowFullScreenContent: (ad, err) {
        ad.dispose();
        _isRewardedAdReady = false;
        debugPrint('AdManager: Rewarded ad failed to show: $err');
        onAdFailed();
        loadRewardedAd(); // Pre-load next ad
      },
    );

    _rewardedAd!.show(
      onUserEarnedReward: (ad, reward) {
        debugPrint('AdManager: User earned reward: ${reward.amount} ${reward.type}');
        onAdRewarded(reward);
      },
    );
  }

  // Interstitial Ad Methods
  void loadInterstitialAd() {
    if (_isInterstitialAdReady) return;
    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isInterstitialAdReady = true;
          _interstitialAd?.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _isInterstitialAdReady = false;
              _onInterstitialAdDismissed?.call();
              _onInterstitialAdDismissed = null;
              loadInterstitialAd();
            },
            onAdFailedToShowFullScreenContent: (ad, err) {
              ad.dispose();
              _isInterstitialAdReady = false;
              _onInterstitialAdDismissed?.call();
              _onInterstitialAdDismissed = null;
              loadInterstitialAd();
            },
          );
        },
        onAdFailedToLoad: (err) {
          _isInterstitialAdReady = false;
        },
      ),
    );
  }

  void showInterstitialAd({VoidCallback? onAdDismissed}) {
    if (_isInterstitialAdReady && _interstitialAd != null) {
      _onInterstitialAdDismissed = onAdDismissed;
      _interstitialAd!.show();
    } else {
      onAdDismissed?.call();
    }
  }

  // Banner Ad Methods
  void loadBannerAd({Function? onAdLoaded}) {
    if (_isBannerAdReady) return;
    _bannerAd = BannerAd(
      adUnitId: bannerAdUnitId,
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          _bannerAd = ad as BannerAd;
          _isBannerAdReady = true;
          onAdLoaded?.call();
        },
        onAdFailedToLoad: (ad, err) {
          ad.dispose();
          _isBannerAdReady = false;
        },
      ),
    );
    _bannerAd?.load();
  }

  Widget? getBannerAdWidget() {
    if (_isBannerAdReady && _bannerAd != null) {
      return SizedBox(
        width: _bannerAd!.size.width.toDouble(),
        height: _bannerAd!.size.height.toDouble(),
        child: AdWidget(ad: _bannerAd!),
      );
    }
    return null;
  }

  void disposeBannerAd() {
    _bannerAd?.dispose();
    _isBannerAdReady = false;
  }

  // Native Ad Methods
  void loadNativeAd({Function? onAdLoaded}) {
    if (!Platform.isAndroid) return;
    if (_isNativeAdReady) return;
    _nativeAd = NativeAd(
      adUnitId: nativeAdUnitId,
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          _nativeAd = ad as NativeAd;
          _isNativeAdReady = true;
          onAdLoaded?.call();
        },
        onAdFailedToLoad: (ad, err) {
          ad.dispose();
          _isNativeAdReady = false;
        },
      ),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.medium,
        mainBackgroundColor: const Color(0xFFFFFFFF),
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: Colors.white,
          backgroundColor: const Color(0xFF007BFF),
          style: NativeTemplateFontStyle.normal,
          size: 16.0,
        ),
        primaryTextStyle: NativeTemplateTextStyle(
          textColor: Colors.black,
          backgroundColor: Colors.transparent,
          style: NativeTemplateFontStyle.bold,
          size: 18.0,
        ),
        secondaryTextStyle: NativeTemplateTextStyle(
          textColor: Colors.grey,
          backgroundColor: Colors.transparent,
          style: NativeTemplateFontStyle.normal,
          size: 14.0,
        ),
        tertiaryTextStyle: NativeTemplateTextStyle(
          textColor: Colors.grey,
          backgroundColor: Colors.transparent,
          style: NativeTemplateFontStyle.normal,
          size: 14.0,
        ),
      ),
    );
    _nativeAd?.load();
  }

  Widget? getNativeAdWidget() {
    if (Platform.isAndroid && _isNativeAdReady && _nativeAd != null) {
      return SizedBox(
        height: 320,
        child: AdWidget(ad: _nativeAd!),
      );
    }
    return null;
  }

  void disposeNativeAd() {
    _nativeAd?.dispose();
    _isNativeAdReady = false;
  }
}
