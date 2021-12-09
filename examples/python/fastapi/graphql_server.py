import json
import os
from typing import Any, List, Optional

import databases
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

# Database Connection
DB_URI = os.environ["DB_URI"]
database = databases.Database(DB_URI)

# Request/Response pydantic models Models
class GraphQLRequest(BaseModel):
    query: str
    variables: Optional[str]


class GraphQLResponse(BaseModel):
    data: Any
    errors: Optional[List[Any]]


# Initialize the App
app = FastAPI()

# Allow CORS
app.add_middleware(
    CORSMiddleware,
    allow_credentials=True,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
async def startup():
    await database.connect()


@app.on_event("shutdown")
async def shutdown():
    await database.disconnect()


@app.post("/rpc/graphql", response_model=GraphQLResponse)
async def graphql(request: GraphQLRequest):
    row = await database.fetch_one(
        query="select graphql.resolve(:query, :variables)",
        values={"query": request.query, "variables": request.variables},
    )
    # Unwrap Optional[Row] -> Row
    assert row is not None
    json_serialized = row["resolve"]
    return json.loads(json_serialized)
