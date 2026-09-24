import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";
import "./brand.css";
import "./spatial.css";
import "./pin-workbench.css";
import {
  GOOGLE_TAG_ID,
  OPENGRAPH_IMAGE_PATH,
  PRIVACY_CONSENT_STORAGE_KEY,
  SITE_URL,
  TWITTER_IMAGE_PATH,
  absoluteUrl,
  localeSeo,
  seoKeywords,
} from "./seo";

const geistSans = Geist({ variable: "--font-geist-sans", subsets: ["latin"] });
const geistMono = Geist_Mono({ variable: "--font-geist-mono", subsets: ["latin"] });
const socialImage = absoluteUrl(OPENGRAPH_IMAGE_PATH);
const twitterImage = absoluteUrl(TWITTER_IMAGE_PATH);
const googleSiteVerification = process.env.NEXT_PUBLIC_GOOGLE_SITE_VERIFICATION?.trim();
const googleTagBootstrap = `
(function initializeGoogleTag() {
window.dataLayer = window.dataLayer || [];
window.gtag = window.gtag || function gtag(){window.dataLayer.push(arguments);};

try {
  var savedPrivacyConsent = window.localStorage.getItem(${JSON.stringify(PRIVACY_CONSENT_STORAGE_KEY)});
  if (savedPrivacyConsent === 'essential') {
    window['ga-disable-' + ${JSON.stringify(GOOGLE_TAG_ID)}] = true;
    window.gtag('consent', 'default', { analytics_storage: 'denied' });
  }
} catch {
  // Preserve the documented default-on policy when local storage is unavailable.
}

window.gtag('js', new Date());
window.gtag('config', ${JSON.stringify(GOOGLE_TAG_ID)});

var googleTagScript = document.createElement('script');
googleTagScript.async = true;
googleTagScript.src = ${JSON.stringify(`https://www.googletagmanager.com/gtag/js?id=${GOOGLE_TAG_ID}`)};
document.head.appendChild(googleTagScript);
})();
`.trim();

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: localeSeo.zh.title,
  description: localeSeo.zh.description,
  applicationName: "PinboardShot",
  authors: [{ name: "PinboardShot" }],
  creator: "PinboardShot",
  publisher: "PinboardShot",
  keywords: seoKeywords,
  icons: {
    icon: [
      { url: "/favicon.ico", sizes: "any" },
      { url: "/icon.png", type: "image/png" },
    ],
    apple: [
      { url: "/apple-icon.png", type: "image/png" },
      { url: "/apple-touch-icon.png", type: "image/png" },
    ],
  },
  alternates: {
    canonical: absoluteUrl("/"),
    languages: {
      "zh-CN": absoluteUrl(localeSeo.zh.path),
      en: absoluteUrl(localeSeo.en.path),
      "x-default": absoluteUrl("/"),
    },
  },
  robots: {
    index: true,
    follow: true,
    googleBot: {
      index: true,
      follow: true,
      "max-image-preview": "large",
      "max-snippet": -1,
    },
  },
  ...(googleSiteVerification
    ? {
        verification: {
          google: googleSiteVerification,
        },
      }
    : {}),
  openGraph: {
    title: localeSeo.zh.title,
    description: localeSeo.zh.description,
    url: absoluteUrl("/"),
    siteName: "PinboardShot",
    type: "website",
    locale: "zh_CN",
    alternateLocale: ["en_US"],
    images: [{ url: socialImage, width: 1920, height: 990, alt: "PinboardShot for macOS" }],
  },
  twitter: {
    card: "summary_large_image",
    title: localeSeo.zh.title,
    description: localeSeo.zh.description,
    images: [twitterImage],
  },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="zh-CN">
      <head>
        <script
          dangerouslySetInnerHTML={{
            __html: googleTagBootstrap,
          }}
        />
      </head>
      <body className={`${geistSans.variable} ${geistMono.variable}`}>{children}</body>
    </html>
  );
}
