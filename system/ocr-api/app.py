import io
import pytesseract
import pdfplumber
from fastapi import FastAPI, UploadFile, File
from pdf2image import convert_from_bytes

app = FastAPI()

@app.get("/health")
def health():
    return {"status": "ok"}

@app.post("/ocr")
async def ocr_pdf(file: UploadFile = File(...)):
    data = await file.read()
    text = ""

    # Fast path: digital PDF with selectable text
    with pdfplumber.open(io.BytesIO(data)) as pdf:
        for page in pdf.pages:
            text += (page.extract_text() or "")

    # Fallback: scanned/image-based PDF — run Tesseract
    if not text.strip():
        images = convert_from_bytes(data)
        text = "\n".join(pytesseract.image_to_string(img) for img in images)

    return {"text": text}