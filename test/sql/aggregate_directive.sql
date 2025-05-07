begin;

-- Create a simple table without any directives
create table product(
    id serial primary key,
    name text not null,
    price numeric not null,
    stock int not null
);

insert into product(name, price, stock)
values
    ('Widget', 9.99, 100),
    ('Gadget', 19.99, 50),
    ('Gizmo', 29.99, 25);

-- Try to query aggregate without enabling the directive - should fail
select graphql.resolve($$
{
  productCollection {
    aggregate {
      count
    }
  }
}
$$);

-- Enable aggregates
comment on table product is e'@graphql({"aggregate": {"enabled": true}})';

-- Now aggregates should be available - should succeed
select graphql.resolve($$
{
  productCollection {
    aggregate {
      count
      sum {
        price
        stock
      }
      avg {
        price
      }
      max {
        price
        name
      }
      min {
        stock
      }
    }
  }
}
$$);

rollback; 