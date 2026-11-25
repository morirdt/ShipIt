from typing import Annotated

from fastapi import Depends, FastAPI, HTTPException, Response, status

from shipit_api.config import Settings, get_settings
from shipit_api.models import Note, NoteCreate, NoteUpdate
from shipit_api.repository import NoteNotFoundError, NotesRepository, get_repository

app = FastAPI(title="ShipIt API")

Repo = Annotated[NotesRepository, Depends(get_repository)]


def _not_found(note_id: str) -> HTTPException:
    return HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Note {note_id} not found")


@app.get("/health")
def health() -> dict[str, str]:
    # Liveness only: does not touch DynamoDB, so a downstream blip
    # does not get the container killed.
    return {"status": "ok"}


@app.get("/version")
def version(settings: Annotated[Settings, Depends(get_settings)]) -> dict[str, str]:
    return {"git_sha": settings.git_sha}


@app.post("/notes", status_code=status.HTTP_201_CREATED)
def create_note(data: NoteCreate, repo: Repo) -> Note:
    return repo.create(data)


@app.get("/notes")
def list_notes(repo: Repo) -> list[Note]:
    return repo.list()


@app.get("/notes/{note_id}")
def get_note(note_id: str, repo: Repo) -> Note:
    try:
        return repo.get(note_id)
    except NoteNotFoundError:
        raise _not_found(note_id) from None


@app.patch("/notes/{note_id}")
def update_note(note_id: str, data: NoteUpdate, repo: Repo) -> Note:
    try:
        return repo.update(note_id, data)
    except NoteNotFoundError:
        raise _not_found(note_id) from None


@app.delete("/notes/{note_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_note(note_id: str, repo: Repo) -> Response:
    try:
        repo.delete(note_id)
    except NoteNotFoundError:
        raise _not_found(note_id) from None
    return Response(status_code=status.HTTP_204_NO_CONTENT)
