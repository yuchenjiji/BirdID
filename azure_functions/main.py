import os
import psycopg2
import psycopg2.extras
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from typing import Optional
import logging

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "POST", "DELETE"],
    allow_headers=["*"],
)


def get_conn():
    return psycopg2.connect(sslmode="require")


class BirdRecord(BaseModel):
    id: str
    uid: str
    commonName: str
    scientificName: str
    score: float
    timestamp: str
    description: Optional[str] = None
    imageUrl: Optional[str] = None


@app.get("/history")
def get_history(uid: str):
    try:
        with get_conn() as conn:
            with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
                cur.execute(
                    """
                    SELECT id,
                           common_name      AS "commonName",
                           scientific_name  AS "scientificName",
                           score,
                           to_char(timestamp AT TIME ZONE 'UTC',
                                   'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS timestamp,
                           description,
                           image_url        AS "imageUrl"
                    FROM bird_history
                    WHERE uid = %s
                    ORDER BY timestamp DESC
                    """,
                    (uid,),
                )
                return list(cur.fetchall())
    except Exception as e:
        logging.exception("get_history error")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/history")
def post_history(record: BirdRecord):
    try:
        with get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    INSERT INTO bird_history
                        (id, uid, common_name, scientific_name, score, timestamp, description, image_url)
                    VALUES (%s, %s, %s, %s, %s, %s::timestamptz, %s, %s)
                    ON CONFLICT (id) DO UPDATE SET
                        description = EXCLUDED.description,
                        image_url   = EXCLUDED.image_url
                    """,
                    (
                        record.id, record.uid, record.commonName, record.scientificName,
                        record.score, record.timestamp, record.description, record.imageUrl,
                    ),
                )
        return {"ok": True}
    except Exception as e:
        logging.exception("post_history error")
        raise HTTPException(status_code=500, detail=str(e))


@app.delete("/history")
def delete_history(uid: str):
    try:
        with get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute("DELETE FROM bird_history WHERE uid = %s", (uid,))
        return {"ok": True}
    except Exception as e:
        logging.exception("delete_history error")
        raise HTTPException(status_code=500, detail=str(e))
