import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import { headers } from "next/headers";
import "./globals.css";
import { localeSeo, seoKeywords } from "./seo";

const geistSans = Geist({ variable: "--font-geist-sans", subsets: ["latin"] });
const geistMono = Geist_Mono({ variable: "--font-geist-mono", subsets: ["latin"] });

export async function generateMetadata(): Promise<Metadata> {
  const requestHeaders = await headers();
  const host = requestHeaders.get("x-forwarded-host") ?? requestHeaders.get("host");
  const protocol = requestHeaders.get("x-forwarded-proto") ?? (host?.startsWith("localhost") ? "http" : "https");
  const baseUrl = host ? `${protocol}://${host}` : "http://localhost:3000";
  const socialImage = new URL("/og.png", baseUrl).toString();
  const canonicalUrl = baseUrl;

  return {
    metadataBase: new URL(baseUrl),
    title: "PinboardShot - Mac 截图、标注与贴图工具",
    description: localeSeo.zh.description,
    applicationName: "PinboardShot",
    authors: [{ name: "PinboardShot" }],
    creator: "PinboardShot",
    publisher: "PinboardShot",
    keywords: seoKeywords,
    alternates: {
      canonical: canonicalUrl,
      languages: {
        "zh-CN": new URL(localeSeo.zh.path, baseUrl).toString(),
        en: new URL(localeSeo.en.path, baseUrl).toString(),
        "x-default": canonicalUrl,
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
    openGraph: {
      title: "PinboardShot - Mac 截图、标注与贴图工具",
      description: localeSeo.zh.description,
      url: canonicalUrl,
      siteName: "PinboardShot",
      type: "website",
      locale: "zh_CN",
      alternateLocale: ["en_US"],
      images: [{ url: socialImage, width: 1792, height: 1024, alt: "PinboardShot for macOS" }],
    },
    twitter: {
      card: "summary_large_image",
      title: "PinboardShot - Mac 截图、标注与贴图工具",
      description: localeSeo.zh.description,
      images: [socialImage],
    },
  };
}

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="zh-CN">
      <body className={`${geistSans.variable} ${geistMono.variable}`}>{children}</body>
    </html>
  );
}
