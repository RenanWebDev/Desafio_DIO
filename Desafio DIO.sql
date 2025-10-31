DROP DATABASE IF EXISTS ecommerce;
CREATE DATABASE ecommerce CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE ecommerce;


CREATE TABLE clients (
  idClient      INT AUTO_INCREMENT PRIMARY KEY,
  Fname         VARCHAR(40) NOT NULL,
  Minit         CHAR(3),
  Lname         VARCHAR(60),
  email         VARCHAR(150) UNIQUE,
  phone         VARCHAR(30),
  tipo          ENUM('PF','PJ') NOT NULL,     -- uma conta é PF *ou* PJ
  address       VARCHAR(255),
  created_at    DATETIME NOT NULL DEFAULT NOW()
);

CREATE TABLE client_pf (
  idClient INT PRIMARY KEY,
  CPF      CHAR(11) NOT NULL UNIQUE,
  birth    DATE,
  CONSTRAINT fk_pf_client FOREIGN KEY (idClient) REFERENCES clients(idClient)
    ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE client_pj (
  idClient INT PRIMARY KEY,
  CNPJ     CHAR(14) NOT NULL UNIQUE,
  ie       VARCHAR(30),
  razao    VARCHAR(160),
  CONSTRAINT fk_pj_client FOREIGN KEY (idClient) REFERENCES clients(idClient)
    ON DELETE CASCADE ON UPDATE CASCADE
);

/* Restrições PF XOR PJ + coerência do tipo */
DELIMITER $$

CREATE TRIGGER trg_only_pf
BEFORE INSERT ON client_pf
FOR EACH ROW
BEGIN
  DECLARE v ENUM('PF','PJ');
  SELECT tipo INTO v FROM clients WHERE idClient = NEW.idClient;
  IF v <> 'PF' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Cliente deve ser PF para entrar em client_pf';
  END IF;
  IF EXISTS (SELECT 1 FROM client_pj WHERE idClient = NEW.idClient) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Cliente já possui PJ (exclusivo)';
  END IF;
END$$

CREATE TRIGGER trg_only_pj
BEFORE INSERT ON client_pj
FOR EACH ROW
BEGIN
  DECLARE v ENUM('PF','PJ');
  SELECT tipo INTO v FROM clients WHERE idClient = NEW.idClient;
  IF v <> 'PJ' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Cliente deve ser PJ para entrar em client_pj';
  END IF;
  IF EXISTS (SELECT 1 FROM client_pf WHERE idClient = NEW.idClient) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Cliente já possui PF (exclusivo)';
  END IF;
END$$
DELIMITER ;

CREATE TABLE supplier(
  idSupplier INT AUTO_INCREMENT PRIMARY KEY,
  socialName VARCHAR(255) NOT NULL,
  CNPJ       CHAR(14) NOT NULL UNIQUE,
  contact    VARCHAR(30) NOT NULL
);

CREATE TABLE seller(
  idSeller  INT AUTO_INCREMENT PRIMARY KEY,
  SocialName VARCHAR(255) NOT NULL,
  AbsName    VARCHAR(255),
  CNPJ       CHAR(14) UNIQUE,
  CPF        CHAR(11) UNIQUE,
  location   VARCHAR(255),
  contact    VARCHAR(30) NOT NULL,
  CHECK (CNPJ IS NOT NULL OR CPF IS NOT NULL)
);

CREATE TABLE product(
  IdProduct          INT AUTO_INCREMENT PRIMARY KEY,
  Pname              VARCHAR(120) NOT NULL,
  classification_kids BOOLEAN DEFAULT FALSE,
  category           ENUM('Eletrônico','Vestimenta','Brinquedos','Alimentos','Móveis') NOT NULL,
  avaliacao          FLOAT DEFAULT 0,
  size               VARCHAR(20),
  price              DECIMAL(10,2) NOT NULL DEFAULT 0.00,  -- adicionado p/ totalização
  fornecedor_id      INT NOT NULL,
  CONSTRAINT fk_prod_supplier FOREIGN KEY (fornecedor_id) REFERENCES supplier(idSupplier)
);

CREATE TABLE productStorage(
  idProdStorage INT AUTO_INCREMENT PRIMARY KEY,
  storageLocation VARCHAR(255),
  quantify INT DEFAULT 0 CHECK (quantify >= 0)
);

/* onde cada produto está estocado (N:N) */
CREATE TABLE storageLocation(
  idLproduct INT,
  idLstorage INT,
  location   VARCHAR(255) NOT NULL,
  PRIMARY KEY (idLproduct, idLstorage),
  CONSTRAINT fk_storage_location_product FOREIGN KEY (idLproduct) REFERENCES product(IdProduct),
  CONSTRAINT fk_storage_location_storage FOREIGN KEY (idLstorage) REFERENCES productStorage(idProdStorage)
);

/* produto x vendedor (catálogo do vendedor) */
CREATE TABLE productSeller(
  idPseller   INT,
  idPproduct  INT,
  prodQuantify INT DEFAULT 1 CHECK (prodQuantify >= 0),
  PRIMARY KEY (idPseller, idPproduct),
  CONSTRAINT fk_product_seller FOREIGN KEY (idPseller) REFERENCES seller(idSeller),
  CONSTRAINT fk_product_product FOREIGN KEY (idPproduct) REFERENCES product(IdProduct)
);

CREATE TABLE productSupplier(
  idPsSupplier INT,
  idPsProduct  INT,
  quantify     INT NOT NULL CHECK (quantify >= 0),
  PRIMARY KEY (idPsSupplier, idPsProduct),
  CONSTRAINT fk_product_supplier_supplier FOREIGN KEY (idPsSupplier) REFERENCES supplier(idSupplier),
  CONSTRAINT fk_product_supplier_product  FOREIGN KEY (idPsProduct)  REFERENCES product(IdProduct)
);

/* PEDIDO, ITENS, PAGAMENTO, ENTREGA */

CREATE TABLE orders(
  idOrder        INT AUTO_INCREMENT PRIMARY KEY,
  idOrderClient  INT NOT NULL,
  orderStatus    ENUM('Cancelado','Confirmado','Em processamento') DEFAULT 'Em processamento',
  orderDescription VARCHAR(255),
  sendValue      DECIMAL(10,2) NOT NULL DEFAULT 10.00,
  paymentCash    BOOLEAN DEFAULT FALSE,
  created_at     DATETIME NOT NULL DEFAULT NOW(),
  CONSTRAINT fk_orders_client FOREIGN KEY (idOrderClient) REFERENCES clients (idClient) ON UPDATE CASCADE
);

CREATE TABLE productOrder(
  idPOproduct INT,
  idPOorder   INT,
  poQuantify  INT DEFAULT 1 CHECK (poQuantify > 0),
  poStatus    ENUM('Disponível','Sem estoque') DEFAULT 'Disponível',
  price_at    DECIMAL(10,2) NOT NULL,                 -- captura o preço no momento
  PRIMARY KEY (idPOproduct, idPOorder),
  CONSTRAINT fk_productorder_product FOREIGN KEY (idPOproduct) REFERENCES product(IdProduct),
  CONSTRAINT fk_productorder_order   FOREIGN KEY (idPOorder)   REFERENCES orders(idOrder)
);

/* pagamentos múltiplos por pedido */
CREATE TABLE payments (
  idPayment     INT AUTO_INCREMENT PRIMARY KEY,
  idOrder       INT NOT NULL,
  typePayment   ENUM('Boleto','Cartão','Dois cartões','PIX','PayPal') NOT NULL,
  amount        DECIMAL(10,2) NOT NULL CHECK (amount >= 0),
  paid_at       DATETIME,
  limitAvailable FLOAT,
  CONSTRAINT fk_pay_order FOREIGN KEY (idOrder) REFERENCES orders(idOrder) ON DELETE CASCADE
);

/* entrega com status + código de rastreio */
CREATE TABLE shipping (
  idShipping   INT AUTO_INCREMENT PRIMARY KEY,
  idOrder      INT NOT NULL UNIQUE,
  status       ENUM('AGUARDANDO','EM_SEPARACAO','EM_TRANSITO','ENTREGUE','DEVOLVIDO','CANCELADO') NOT NULL DEFAULT 'AGUARDANDO',
  trackingCode VARCHAR(60) NOT NULL UNIQUE,
  updated_at   DATETIME NOT NULL DEFAULT NOW(),
  CONSTRAINT fk_ship_order FOREIGN KEY (idOrder) REFERENCES orders(idOrder) ON DELETE CASCADE
);

/* DADOS DE TESTE */

-- Clients
INSERT INTO clients (Fname,Minit,Lname,email,phone,tipo,address) VALUES
('Ana','M','Silva','ana@ex.com','62999990001','PF','Rua A, 100'),
('Tech',NULL,'LTDA','contato@tech.com','6233330002','PJ','Av. B, 200'),
('Bruno',NULL,'Souza','bruno@ex.com','62999990003','PF','Rua C, 300');

INSERT INTO client_pf VALUES
(1,'12345678901','1995-04-20'),
(3,'98765432100','1992-01-10');

INSERT INTO client_pj VALUES
(2,'11222333444455','IS123','Tech LTDA');

-- Suppliers
INSERT INTO supplier (socialName,CNPJ,contact) VALUES
('Alpha Suprimentos','00111222000133','6200001000'),
('Bruno Souza ME','98765432100001','6200002000');

-- Sellers (Bruno aparece nos dois para testarmos o cruzamento)
INSERT INTO seller (SocialName,AbsName,CNPJ,CPF,location,contact) VALUES
('Carla Ramos ME','Carla Ramos','22333444000155',NULL,'Goiânia','6200003000'),
('Bruno Souza ME','Bruno Souza',NULL,'98765432100','Goiânia','6200004000');

-- Products
INSERT INTO product (Pname,classification_kids,category,avaliacao,size,price,fornecedor_id) VALUES
('Mouse Óptico',FALSE,'Eletrônico',4.5,NULL,49.90,1),
('Teclado Mec',FALSE,'Eletrônico',4.8,NULL,299.00,1),
('Câmera USB',FALSE,'Eletrônico',4.1,NULL,199.00,2);

-- Product-Seller
INSERT INTO productSeller VALUES
(1,1,20),
(1,2,10),
(2,3,5);

-- Storage & location
INSERT INTO productStorage (storageLocation,quantify) VALUES
('CD-GO',150),('CD-SP',60);

INSERT INTO storageLocation VALUES
(1,1,'CD-GO'),(2,1,'CD-GO'),(3,2,'CD-SP');

-- Orders
INSERT INTO orders (idOrderClient,orderStatus,orderDescription,sendValue,paymentCash,created_at) VALUES
(1,'Confirmado','Pedido Ana',15.00,FALSE,'2025-10-25 10:10:00'),
(2,'Confirmado','Pedido Tech',25.00,FALSE,'2025-10-26 09:00:00'),
(1,'Em processamento','Reposição Ana',15.00,TRUE,'2025-10-27 12:30:00');

-- Order items (captura preço do momento)
INSERT INTO productOrder VALUES
(1,1,2,'Disponível',49.90),     -- 2 mouses
(2,1,1,'Disponível',299.00),    -- 1 teclado
(3,2,1,'Disponível',199.00),    -- 1 câmera
(1,3,1,'Disponível',49.90);

-- Pagamentos múltiplos
INSERT INTO payments (idOrder,typePayment,amount,paid_at) VALUES
(1,'PIX',200.00,'2025-10-25 10:15:00'),
(1,'Cartão',198.90,'2025-10-25 10:16:00'),
(2,'Boleto',199.00,'2025-10-26 11:00:00');

-- Shipping
INSERT INTO shipping (idOrder,status,trackingCode,updated_at) VALUES
(1,'EM_SEPARACAO','BR123-AAA','2025-10-25 11:00:00'),
(2,'EM_TRANSITO','BR456-BBB','2025-10-26 15:00:00');

/* VIEWS (EXPRESSÕES DERIVADAS) */

-- Totais por item
CREATE OR REPLACE VIEW vw_item_totais AS
SELECT
  po.idPOorder     AS order_id,
  po.idPOproduct   AS product_id,
  p.Pname          AS product,
  po.poQuantify    AS qty,
  po.price_at      AS unit_price,
  (po.poQuantify * po.price_at) AS total_item
FROM productOrder po
JOIN product p ON p.IdProduct = po.idPOproduct;

-- Totais por pedido
CREATE OR REPLACE VIEW vw_pedido_totais AS
SELECT
  o.idOrder        AS order_id,
  o.idOrderClient  AS client_id,
  c.Fname          AS cliente,
  SUM(po.poQuantify * po.price_at) AS subtotal_itens,
  o.sendValue,
  SUM(po.poQuantify * po.price_at) + o.sendValue AS total_pedido
FROM orders o
JOIN productOrder po ON po.idPOorder = o.idOrder
JOIN clients c ON c.idClient = o.idOrderClient
GROUP BY o.idOrder, o.idOrderClient, c.Fname, o.sendValue;

/* CONSULTAS (requeridas no desafio) */

-- 1) Quantos pedidos foram feitos por cada cliente? (GROUP BY + HAVING + ORDER BY)
SELECT
  c.idClient,
  CONCAT_WS(' ', c.Fname, c.Lname) AS cliente,
  COUNT(o.idOrder) AS qtde_pedidos
FROM clients c
LEFT JOIN orders o ON o.idOrderClient = c.idClient
GROUP BY c.idClient, cliente
HAVING COUNT(o.idOrder) >= 0
ORDER BY qtde_pedidos DESC, cliente;

-- 2) Algum vendedor também é fornecedor? (JOIN por documento)
SELECT
  s.idSeller, s.SocialName AS vendedor, COALESCE(s.CNPJ,s.CPF) AS doc_vendedor,
  f.idSupplier, f.socialName AS fornecedor, f.CNPJ AS doc_fornecedor
FROM seller s
JOIN supplier f
  ON (s.CNPJ IS NOT NULL AND s.CNPJ = f.CNPJ)
   OR (s.CPF  IS NOT NULL AND s.CPF  = REPLACE(f.CNPJ,'/',''))  -- apenas exemplo
;

-- 3) Relação de produtos, fornecedores e estoques (JOINs + ORDER BY)
SELECT
  p.IdProduct, p.Pname AS produto,
  f.socialName AS fornecedor,
  sl.location  AS local_estoque
FROM product p
JOIN supplier f ON f.idSupplier = p.fornecedor_id
LEFT JOIN storageLocation sl ON sl.idLproduct = p.IdProduct
ORDER BY fornecedor, produto, local_estoque;

-- 4) Relação de nomes dos fornecedores e nomes dos produtos
SELECT f.socialName AS fornecedor, p.Pname AS produto
FROM supplier f
JOIN product  p ON p.fornecedor_id = f.idSupplier
ORDER BY f.socialName, p.Pname;

-- 5) Clientes com gasto total acima de X (expressão derivada + HAVING)
SELECT
  v.client_id,
  v.cliente,
  ROUND(SUM(v.total_pedido),2) AS gasto_total
FROM vw_pedido_totais v
GROUP BY v.client_id, v.cliente
HAVING SUM(v.total_pedido) > 300
ORDER BY gasto_total DESC;

-- 6) Pedidos com valor pago x valor devido (JOIN + expressão)
SELECT
  v.order_id,
  v.cliente,
  v.total_pedido,
  COALESCE(SUM(p.amount),0) AS total_pago,
  (v.total_pedido - COALESCE(SUM(p.amount),0)) AS saldo_a_pagar
FROM vw_pedido_totais v
LEFT JOIN payments p ON p.idOrder = v.order_id
GROUP BY v.order_id, v.cliente, v.total_pedido
ORDER BY saldo_a_pagar DESC;

-- 7) Entregas com status e código de rastreio
SELECT
  o.idOrder, c.Fname AS cliente, s.status, s.trackingCode, s.updated_at
FROM shipping s
JOIN orders o  ON o.idOrder = s.idOrder
JOIN clients c ON c.idClient = o.idOrderClient
ORDER BY s.updated_at DESC;

-- 8) Itens por pedido (com total do item) e filtro (WHERE)
SELECT * FROM vw_item_totais
WHERE total_item >= 100
ORDER BY total_item DESC;
