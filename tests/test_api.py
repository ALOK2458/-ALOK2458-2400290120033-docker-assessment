import sys
import unittest
from datetime import datetime, timezone
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))

import psycopg2
from app import app


class RegistrationApiTests(unittest.TestCase):
    def setUp(self):
        app.config.update(TESTING=True)
        self.client = app.test_client()

    @patch("app.run_sql")
    def test_health_reports_database_connected(self, run_sql):
        response = self.client.get("/api/health")

        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json["database"])
        self.assertIn("regno", response.json)
        self.assertIn("version", response.json)
        self.assertIn("container", response.json)
        run_sql.assert_called_once_with("SELECT 1")

    @patch("app.run_sql", side_effect=psycopg2.OperationalError("database down"))
    def test_health_reports_database_unavailable(self, _run_sql):
        response = self.client.get("/api/health")

        self.assertEqual(response.status_code, 200)
        self.assertFalse(response.json["database"])

    @patch("app.run_sql", return_value=[(7,)])
    def test_registration_creation_returns_created(self, run_sql):
        response = self.client.post(
            "/api/registrations",
            json={"name": "  Example Student ", "event": " Hackathon "},
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(
            response.json,
            {"id": 7, "name": "Example Student", "event": "Hackathon"},
        )
        run_sql.assert_called_once_with(
            "INSERT INTO registrations (name, event) VALUES (%s, %s) RETURNING id",
            ("Example Student", "Hackathon"),
            fetch=True,
        )

    def test_missing_name_returns_bad_request(self):
        response = self.client.post(
            "/api/registrations", json={"event": "Hackathon"}
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn("error", response.json)

    def test_missing_event_returns_bad_request(self):
        response = self.client.post(
            "/api/registrations", json={"name": "Example Student"}
        )

        self.assertEqual(response.status_code, 400)
        self.assertIn("error", response.json)

    def test_non_object_and_blank_data_return_bad_request(self):
        for payload in ([], {"name": " ", "event": "Hackathon"}, None):
            with self.subTest(payload=payload):
                response = self.client.post("/api/registrations", json=payload)
                self.assertEqual(response.status_code, 400)

    @patch(
        "app.run_sql",
        return_value=[
            (
                7,
                "Example Student",
                "Hackathon",
                datetime(2026, 10, 28, 8, 0, tzinfo=timezone.utc),
            )
        ],
    )
    def test_registration_listing_returns_json(self, run_sql):
        response = self.client.get("/api/registrations")

        self.assertEqual(response.status_code, 200)
        self.assertEqual(
            response.json,
            [
                {
                    "id": 7,
                    "name": "Example Student",
                    "event": "Hackathon",
                    "created": "2026-10-28T08:00:00+00:00",
                }
            ],
        )
        run_sql.assert_called_once_with(
            "SELECT id, name, event, created FROM registrations ORDER BY id",
            fetch=True,
        )

    @patch("app.run_sql", side_effect=psycopg2.OperationalError("database down"))
    def test_database_errors_on_registration_list_return_service_unavailable(
        self, _run_sql
    ):
        response = self.client.get("/api/registrations")

        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.json, {"error": "database unavailable"})


if __name__ == "__main__":
    unittest.main()
