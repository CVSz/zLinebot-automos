import fs from "node:fs";
import PDFDocument from "pdfkit";

export function generateReport(data, outputPath = "report.pdf") {
  const doc = new PDFDocument({ margin: 50 });
  doc.pipe(fs.createWriteStream(outputPath));

  doc.fontSize(20).text("Fund Performance Report");
  doc.moveDown();
  doc.fontSize(12).text(`Generated: ${new Date().toISOString()}`);
  doc.text(`Portfolio Value: ${data.value ?? "n/a"}`);
  doc.text(`PnL: ${data.pnl ?? "n/a"}`);
  doc.text(`Sharpe: ${data.sharpe ?? "n/a"}`);

  if (Array.isArray(data.notes) && data.notes.length > 0) {
    doc.moveDown();
    doc.fontSize(14).text("Notes");
    data.notes.forEach((note) => doc.fontSize(12).text(`- ${note}`));
  }

  doc.end();
  return outputPath;
}
