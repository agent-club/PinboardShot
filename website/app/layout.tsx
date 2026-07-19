import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import { headers } from "next/headers";
import "./globals.css";

const geistSans = Geist({ variable: "--font-geist-sans", subsets: ["latin"] });
const geistMono = Geist_Mono({ variable: "--font-geist-mono", subsets: ["latin"] });

export async function generateMetadata(): Promise<Metadata> {
  const requestHeaders = await headers();
  const host = requestHeaders.get("x-forwarded-host") ?? requestHeaders.get("host");
  const protocol = requestHeaders.get("x-forwarded-proto") ?? (host?.startsWith("localhost") ? "http" : "https");
  const baseUrl = host ? `${protocol}://${host}` : "http://localhost:3000";
  const socialImage = new URL("/og.png", baseUrl).toString();

  return {
    title: "PinboardShot — Capture it. Keep it in sight.",
    description: "A native, private capture, annotation, and pinboard tool for macOS. Mark up screenshots, export from Native Retina to 8K, and keep references floating above your work.",
    keywords: ["PinboardShot", "macOS screenshot", "screenshot annotation", "screen pin", "8K screenshot", "local-first"],
    openGraph: {
      title: "PinboardShot — Capture it. Keep it in sight.",
      description: "Native macOS capture, annotation, and pinning — fully local, from Retina to 8K.",
      type: "website",
      images: [{ url: socialImage, width: 1792, height: 1024, alt: "PinboardShot for macOS" }],
    },
    twitter: {
      card: "summary_large_image",
      title: "PinboardShot — Capture it. Keep it in sight.",
      description: "Native macOS capture, annotation, and pinning — fully local, from Retina to 8K.",
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
